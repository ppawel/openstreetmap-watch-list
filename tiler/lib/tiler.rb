require 'logging'
require 'utils'
require 'ffi-geos'

module Tiler

# Implements tiling logic.
class Tiler
  include ::Tiler::Logger

  attr_accessor :conn

  def initialize(conn)
    @conn = conn
    @wkb_reader = Geos::WkbReader.new
    @wkt_reader = Geos::WktReader.new
    @wkb_writer = Geos::WkbWriter.new
    prepare_db
  end

  ##
  # Generates tiles for given zoom and changeset.
  #
  def generate(zoom, changeset_id, options = {})
    tile_count = nil
    @conn.transaction do |c|
      generate_changes(changeset_id) if options[:changes]
      tile_count = do_generate(zoom, changeset_id, options)
    end
    tile_count
  end

  ##
  # Removes tiles for given zoom and changeset. This is useful when retiling (creating new tiles) to avoid
  # duplicate primary key error during insert.
  #
  def clear_tiles(changeset_id, zoom)
    #@conn.exec("DELETE FROM changes WHERE changeset_id = #{changeset_id}")
    count = @conn.exec("DELETE FROM tiles WHERE changeset_id = #{changeset_id} AND zoom = #{zoom}").cmd_tuples
    @@log.debug "Removed existing tiles: #{count}"
    count
  end

  protected

  def do_generate(zoom, changeset_id, options = {})
    clear_tiles(changeset_id, zoom) if options[:retile]

    @conn.exec('TRUNCATE _tile_changes_tmp')

    for change in @conn.exec("SELECT id, el_id, el_version, el_type, tstamp, geom, prev_geom,
          CASE WHEN el_type = 'N' THEN ST_X(prev_geom) ELSE NULL END AS prev_lon,
          CASE WHEN el_type = 'N' THEN ST_Y(prev_geom) ELSE NULL END AS prev_lat,
          CASE WHEN el_type = 'N' THEN ST_X(geom) ELSE NULL END AS lon,
          CASE WHEN el_type = 'N' THEN ST_Y(geom) ELSE NULL END AS lat,
          Box2D(ST_Collect(prev_geom, geom)) AS both_bbox
        FROM changes WHERE changeset_id = #{changeset_id}").to_a
      change['geom_obj'] = @wkb_reader.read_hex(change['geom'])
      change['prev_geom_obj'] = @wkb_reader.read_hex(change['prev_geom']) if change['prev_geom']
      if change['el_type'] == 'N'
        @@log.debug "Node #{change['el_id']} (#{change['el_version']})"
        create_node_tiles(changeset_id, change, change['id'].to_i, zoom)
      elsif change['el_type'] == 'W'
        @@log.debug "Way #{change['el_id']} (#{change['el_version']})"
        create_way_tiles(changeset_id, change, change['id'].to_i, zoom, options)
      end
    end

    count = @conn.exec("INSERT INTO tiles (changeset_id, tstamp, zoom, x, y, changes, geom, prev_geom)
      SELECT  #{changeset_id}, MAX(tstamp) AS tstamp, zoom, x, y,
        array_agg(change_id), array_agg(geom), array_agg(prev_geom)
      FROM _tile_changes_tmp tmp
      GROUP BY zoom, x, y").cmd_tuples

    @@log.debug "Aggregating tiles..."

    # Now generate tiles at lower zoom levels.
    (3..16).reverse_each do |i|
      @conn.exec("SELECT OWL_AggregateChangeset(#{changeset_id}, #{i}, #{i - 1})")
    end

    count
  end

  def create_node_tiles(changeset_id, node, change_id, zoom)
    tile = latlon2tile(node['lat'].to_f, node['lon'].to_f, zoom)
    prev_tile = nil
    prev_tile = latlon2tile(node['prev_lat'].to_f, node['prev_lon'].to_f, zoom) if node['prev_lat']

    if tile == prev_tile
      @conn.exec("INSERT INTO _tile_changes_tmp (el_type, tstamp, zoom, x, y, geom, prev_geom, change_id) VALUES
        ('N', '#{node['tstamp']}', #{zoom}, #{tile[0]}, #{tile[1]},
        ST_SetSRID(ST_GeomFromText('POINT(#{node['lon']} #{node['lat']})'), 4326),
        ST_SetSRID(ST_GeomFromText('POINT(#{node['prev_lon']} #{node['prev_lat']})'), 4326), #{change_id})")
    else
      @conn.exec("INSERT INTO _tile_changes_tmp (el_type, tstamp, zoom, x, y, geom, prev_geom, change_id) VALUES
        ('N', '#{node['tstamp']}', #{zoom}, #{tile[0]}, #{tile[1]},
        ST_SetSRID(ST_GeomFromText('POINT(#{node['lon']} #{node['lat']})'), 4326), NULL, #{change_id})")

      if prev_tile
        @conn.exec("INSERT INTO _tile_changes_tmp (el_type, tstamp, zoom, x, y, geom, prev_geom, change_id) VALUES
          ('N', '#{node['tstamp']}', #{zoom}, #{prev_tile[0]}, #{prev_tile[1]},
          NULL, ST_SetSRID(ST_GeomFromText('POINT(#{node['prev_lon']} #{node['prev_lat']})'), 4326), #{change_id})")
      end
    end
  end

  def create_way_tiles(changeset_id, way, change_id, zoom, options)
    tile_count = bbox_tile_count(zoom, box2d_to_bbox(way["both_bbox"]))

    @@log.debug "  tile_count = #{tile_count}"

    # Does not make sense to try to reduce small ways.
    if tile_count < 64
      tiles = bbox_to_tiles(zoom, box2d_to_bbox(way["both_bbox"]))
    else
      tiles = reduce_tiles(changeset_id, way, zoom)
    end

    @@log.debug "  Processing #{tiles.size} tile(s)..."

    count = 0

    for tile in tiles
      x, y = tile[0], tile[1]
      lat1, lon1 = tile2latlon(x, y, zoom)
      lat2, lon2 = tile2latlon(x + 1, y + 1, zoom)
      #@conn.exec("INSERT INTO _tile_bboxes VALUES (#{x}, #{y}, #{zoom},
      #  ST_SetSRID('BOX(#{lon1} #{lat1},#{lon2} #{lat2})'::box2d, 4326))")
      tile_geom = @wkt_reader.read("MULTIPOINT(#{lon1} #{lat1},#{lon2} #{lat2})").envelope

      if tile_geom.intersects?(way['geom_obj'])
        count += @conn.exec("INSERT INTO _tile_changes_tmp (el_type, tstamp, zoom, x, y, geom, prev_geom, change_id) VALUES (
          'W', '#{way['tstamp']}', #{zoom}, #{x}, #{y}, '#{way['geom']}', #{way['prev_geom'] ? "'#{way['geom']}'" : 'NULL'}, #{change_id})").cmd_tuples
      end
    end

    @@log.debug "  Created #{count} tile(s)"
  end

  def reduce_tiles(changeset_id, change, zoom)
    tiles = Set.new
    for source_zoom in [14]
      for tile in bbox_to_tiles(source_zoom, box2d_to_bbox(change["both_bbox"]))
        x, y = tile[0], tile[1]
        lat1, lon1 = tile2latlon(x, y, source_zoom)
        lat2, lon2 = tile2latlon(x + 1, y + 1, source_zoom)
        tile_geom = @wkt_reader.read("MULTIPOINT(#{lon1} #{lat1},#{lon2} #{lat2})").envelope

        intersects = tile_geom.intersects?(change['geom_obj'])
        tiles.merge(subtiles(tile, source_zoom, zoom)) if intersects and source_zoom == 14
      end
    end
    tiles
  end

  def generate_changes(changeset_id)
    @conn.exec("DELETE FROM changes WHERE changeset_id = #{changeset_id}")
    @conn.exec("INSERT INTO changes
      (changeset_id, tstamp, el_type, el_id, el_version, el_action, geom_changed, tags_changed, nodes_changed,
        members_changed, geom, prev_geom, tags, prev_tags, nodes, prev_nodes)
      SELECT * FROM OWL_GenerateChanges(#{changeset_id})")
  end

  def prepare_db
    @conn.exec('CREATE TEMPORARY TABLE _tile_changes_tmp (el_type element_type NOT NULL, tstamp timestamp without time zone,
      x int, y int, zoom int, geom geometry, prev_geom geometry, change_id bigint NOT NULL)')
  end
end

end
