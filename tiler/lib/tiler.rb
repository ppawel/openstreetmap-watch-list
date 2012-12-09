require 'logging'
require 'utils'

module Tiler

# Implements tiling logic.
class Tiler
  include ::Tiler::Logger

  attr_accessor :conn

  def initialize(conn)
    @conn = conn
    #@conn.exec('DROP TABLE IF EXISTS _way_geom')
    #@conn.exec('DROP TABLE IF EXISTS _tile_bboxes')
    #@conn.exec('DROP TABLE IF EXISTS _tile_changes_tmp')
    @conn.exec('CREATE TEMPORARY TABLE _way_geom (geom geometry, prev_geom geometry, tstamp timestamp without time zone)')
    @conn.exec('CREATE TEMPORARY TABLE _tile_bboxes (x int, y int, zoom int, tile_bbox geometry)')
    @conn.exec('CREATE TEMPORARY TABLE _tile_changes_tmp (el_type element_type NOT NULL, tstamp timestamp without time zone,
      x int, y int, zoom int, geom geometry, prev_geom geometry)')
    @conn.exec('CREATE TEMPORARY TABLE _changeset_data (
      type varchar(2),
      id bigint,
      version int,
      tstamp timestamp without time zone,
      tags hstore,
      geom geometry,
      nodes bigint[],
      prev_version int,
      prev_tags hstore,
      prev_geom geometry,
      prev_nodes bigint[])')
    @conn.exec('CREATE INDEX _idx_way_geom ON _way_geom USING gist (geom)')
    @conn.exec('CREATE INDEX _idx_bboxes ON _tile_bboxes USING gist (tile_bbox)')
  end

  ##
  # Generates tiles for given zoom and changeset.
  #
  def generate(zoom, changeset_id, options = {})
    setup_changeset_data(changeset_id)

    tile_count = -1
    #begin
      @conn.transaction do |c|
        tile_count = do_generate(zoom, changeset_id, options)
      end
=begin
rescue
      puts $!
      @@log.debug "Trying workaround..."
      @conn.transaction do |c|
        tile_count = do_generate(zoom, changeset_id, options.merge(:geos_bug_workaround => true))
      end
    end
=end
    clear_changeset_data
    tile_count
  end

  ##
  # Retrieves a list of changeset ids according to given options. If --retile option is NOT specified then
  # changesets that already have tiles in the database are skipped.
  #
  def get_changeset_ids(options)
    if options[:changesets] == ['all']
      # Select changesets with geometry (bbox not null).
      sql = "SELECT id FROM changesets cs WHERE bbox IS NOT NULL"

      unless options[:retile]
        # We are NOT retiling so skip changesets that have been already tiled.
        sql += " AND NOT EXISTS (SELECT 1 FROM tiles WHERE changeset_id = cs.id)"
      end

      sql += " ORDER BY id LIMIT 1000"

      @conn.query(sql).collect {|row| row['id'].to_i}
    else
      # List of changeset ids must have been provided.
      options[:changesets]
    end
  end

  ##
  # Removes tiles for given zoom and changeset. This is useful when retiling (creating new tiles) to avoid
  # duplicate primary key error during insert.
  #
  def clear_tiles(changeset_id, zoom)
    count = @conn.query("DELETE FROM tiles WHERE changeset_id = #{changeset_id} AND zoom = #{zoom}").cmd_tuples
    @@log.debug "Removed existing tiles: #{count}"
    count
  end

  protected

  def do_generate(zoom, changeset_id, options = {})
    clear_tiles(changeset_id, zoom) if options[:retile]

    @conn.exec('TRUNCATE _tile_changes_tmp')
    @conn.exec('TRUNCATE _way_geom')
    @conn.exec('TRUNCATE _tile_bboxes')

    while row = next_changeset_row do
      if row['type'] == 'N'
        process_node(changeset_id, row, zoom)
      elsif row['type'] == 'W'
        process_way(changeset_id, row, zoom, options)
      end
      remove_changeset_row(row)
    end

    # The following is a hack because of http://trac.osgeo.org/geos/ticket/600
    # First, try ST_Union (which will result in a simpler tile geometry), if that fails, go with ST_Collect.
    if !options[:geos_bug_workaround]
      count = @conn.query("INSERT INTO tiles (changeset_id, tstamp, zoom, x, y, changes, geom, prev_geom)
        SELECT  #{changeset_id}, MAX(tstamp) AS tstamp, zoom, x, y, ARRAY[]::bigint[], array_agg(geom), array_agg(prev_geom)--ST_Union(tile_geom)
        FROM _tile_changes_tmp tmp
        GROUP BY zoom, x, y").cmd_tuples
    else
      count = @conn.query("INSERT INTO tiles (changeset_id, tstamp, zoom, x, y, geom)
        SELECT  #{changeset_id}, MAX(tstamp) AS tstamp, zoom, x, y, ST_Collect(tile_geom)
        FROM _tile_changes_tmp tmp
        GROUP BY zoom, x, y").cmd_tuples
    end

    # Now generate tiles at lower zoom levels.
    #(3..16).reverse_each do |i|
    #  @@log.debug "Aggregating tiles for level #{i - 1}..."
    #  @conn.query("SELECT OWL_AggregateChangeset(#{changeset_id}, #{i}, #{i - 1})")
    #end

    count
  end

  def process_node(changeset_id, node, zoom)
    create_node_change(changeset_id, node, zoom)
    create_node_tiles(changeset_id, node, zoom)
  end

  def create_node_tiles(changeset_id, node, zoom)
    if node['lat']
      tile = latlon2tile(node['lat'].to_f, node['lon'].to_f, zoom)
      @conn.query("INSERT INTO _tile_changes_tmp (el_type, tstamp, zoom, x, y, geom, prev_geom) VALUES
        ('N', '#{node['tstamp']}', #{zoom}, #{tile[0]}, #{tile[1]},
        ST_SetSRID(ST_GeomFromText('POINT(#{node['lon']} #{node['lat']})'), 4326), NULL)")
    end

    if node['prev_lat']
      tile = latlon2tile(node['prev_lat'].to_f, node['prev_lon'].to_f, zoom)
      @conn.query("INSERT INTO _tile_changes_tmp (el_type, tstamp, zoom, x, y, geom, prev_geom) VALUES
        ('N', '#{node['tstamp']}', #{zoom}, #{tile[0]}, #{tile[1]},
        NULL, ST_SetSRID(ST_GeomFromText('POINT(#{node['prev_lon']} #{node['prev_lat']})'), 4326))")
    end
  end

  def process_way(changeset_id, way, zoom, options)
    create_way_change(changeset_id, way)
    create_way_tiles(changeset_id, way, zoom, options)
  end

  def create_way_tiles(changeset_id, way, zoom, options)
    @conn.exec('TRUNCATE _tile_bboxes')
    @conn.exec('TRUNCATE _way_geom')

    @conn.query("INSERT INTO _way_geom (geom, prev_geom, tstamp)
      SELECT geom, prev_geom, tstamp
      FROM _changeset_data WHERE id = #{way['id']} AND version = #{way['version']}")

    tiles = bbox_to_tiles(zoom, box2d_to_bbox(way["both_bbox"]))

    @@log.debug "Way #{way['id']} (#{way['version']}): processing #{tiles.size} tile(s)..."

    # Does not make sense to try to reduce small ways.
    if tiles.size > 16
      size_before = tiles.size
      reduce_tiles(tiles, changeset_id, way, zoom)
      @@log.debug "Way #{way['id']} (#{way['version']}): reduced tiles: #{size_before} -> #{tiles.size}"
    end

    for tile in tiles
      x, y = tile[0], tile[1]
      lat1, lon1 = tile2latlon(x, y, zoom)
      lat2, lon2 = tile2latlon(x + 1, y + 1, zoom)

      @conn.query("INSERT INTO _tile_bboxes VALUES (#{x}, #{y}, #{zoom},
        ST_SetSRID('BOX(#{lon1} #{lat1},#{lon2} #{lat2})'::box2d, 4326))")
    end

    @@log.debug "Way #{way['id']} (#{way['version']}): created bboxes..."

    count = @conn.query("INSERT INTO _tile_changes_tmp (el_type, tstamp, zoom, x, y, geom, prev_geom)
      SELECT 'W', tstamp, bb.zoom, bb.x, bb.y, ST_Intersection(geom, bb.tile_bbox), ST_Intersection(prev_geom, bb.tile_bbox)
      FROM _tile_bboxes bb, _way_geom
      WHERE ST_Intersects(geom, bb.tile_bbox) OR ST_Intersects(prev_geom, bb.tile_bbox)").cmd_tuples

    @@log.debug "Way #{way['id']} (#{way['version']}): created #{count} tile(s)"
  end

  def create_node_change(changeset_id, node, zoom)
    origin = 'NODE_MOVED' if node['geom_changed']
    origin = 'NODE_TAGS_CHANGED' if node['tags_changed']
    @conn.query("INSERT INTO changes (tstamp, el_type, el_id, el_version,
      origin, origin_el_type, origin_el_id, origin_el_version, origin_el_action) VALUES (
      '#{node['tstamp']}', 'N', #{node['id']}, #{node['version']},
      '#{origin}', 'N', #{node['id']}, #{node['version']}, 'MODIFY')")
  end

  def create_way_change(changeset_id, way)
    origin = 'WAY_NODES_CHANGED' if way['nodes_changed']
    origin = 'WAY_TAGS_CHANGED' if way['tags_changed']
    @conn.query("INSERT INTO changes (tstamp, el_type, el_id, el_version,
      origin, origin_el_type, origin_el_id, origin_el_version, origin_el_action) VALUES (
      '#{way['tstamp']}', 'W', #{way['id']}, #{way['version']},
      '#{origin}', 'N', #{way['id']}, #{way['version']}, 'MODIFY')")
  end

  def reduce_tiles(tiles, changeset_id, change, zoom)
    for source_zoom in [4, 6, 8, 10, 11, 12, 13, 14]
      for tile in bbox_to_tiles(source_zoom, box2d_to_bbox(change["both_bbox"]))
        x, y = tile[0], tile[1]
        lat1, lon1 = tile2latlon(x, y, source_zoom)
        lat2, lon2 = tile2latlon(x + 1, y + 1, source_zoom)
        intersects = @conn.query("
          SELECT ST_Intersects(ST_SetSRID('BOX(#{lon1} #{lat1},#{lon2} #{lat2})'::box2d, 4326), geom)
          FROM _way_geom").getvalue(0, 0) == 't'
        tiles.subtract(subtiles(tile, source_zoom, zoom)) if !intersects
      end
    end
  end

  def next_changeset_row
    result = @conn.query("SELECT type, id, tstamp, version,
        CASE WHEN type = 'N' THEN ST_X(prev_geom) ELSE NULL END AS prev_lon,
        CASE WHEN type = 'N' THEN ST_Y(prev_geom) ELSE NULL END AS prev_lat,
        CASE WHEN type = 'N' THEN ST_X(geom) ELSE NULL END AS lon,
        CASE WHEN type = 'N' THEN ST_Y(geom) ELSE NULL END AS lat,
        Box2D(ST_Collect(prev_geom, geom)) AS both_bbox,
        NOT ST_Equals(geom, prev_geom) AS geom_changed,
        tags != prev_tags AS tags_changed,
        nodes != prev_nodes AS nodes_changed
      FROM _changeset_data
      ORDER BY type, id, version")
    return nil if result.ntuples == 0
    return result.to_a[0]
  end

  def remove_changeset_row(row)
    @conn.query("DELETE FROM _changeset_data
      WHERE type = '#{row['type']}' AND id = #{row['id']} AND version = #{row['version']}")
  end

  def setup_changeset_data(changeset_id)
    @conn.query("INSERT INTO _changeset_data SELECT * FROM OWL_GetChangesetData(#{changeset_id})").to_a
  end

  def clear_changeset_data
    @conn.query("TRUNCATE _changeset_data")
  end
end

end
