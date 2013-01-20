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
    setup_prepared_statements
    @wkb_reader = Geos::WkbReader.new
    @wkt_reader = Geos::WktReader.new
    @wkb_writer = Geos::WkbWriter.new
    @wkb_writer.include_srid = true
  end

  ##
  # Generates tiles for given zoom and changeset.
  #
  def generate(zoom, changeset_id, options = {})
    tile_count = nil
    @conn.transaction do |c|
      @tiles = {}
      generate_changes(changeset_id) if options[:changes] or !has_changes(changeset_id)
      tile_count = do_generate(zoom, changeset_id, options)
    end
    tile_count
  end

  ##
  # Removes tiles for given zoom and changeset. This is useful when retiling (creating new tiles) to avoid
  # duplicate primary key error during insert.
  #
  def clear_tiles(changeset_id, zoom)
    count = @conn.exec("DELETE FROM tiles WHERE changeset_id = #{changeset_id} AND zoom = #{zoom}").cmd_tuples
    @@log.debug "Removed existing tiles: #{count}"
    count
  end

  def has_tiles(changeset_id)
    @conn.exec("SELECT COUNT(*) FROM tiles WHERE changeset_id = #{changeset_id}").getvalue(0, 0).to_i > 0
  end

  def has_changes(changeset_id)
    @conn.exec("SELECT COUNT(*) FROM changes WHERE changeset_id = #{changeset_id}").getvalue(0, 0).to_i > 0
  end

  protected

  def do_generate(zoom, changeset_id, options = {})
    if options[:retile]
      clear_tiles(changeset_id, zoom)
    else
      return -1 if has_tiles(changeset_id)
    end

    for change in @conn.exec_prepared('select_changes', [changeset_id]).to_a

      change['geom_changed'] = (change['geom_changed'] == 't')
      change['geom_obj'] = @wkb_reader.read_hex(change['geom']) if change['geom']
      change['prev_geom_obj'] = @wkb_reader.read_hex(change['prev_geom']) if change['prev_geom']
      change['diff_geom_obj'] =  change['geom_obj'].difference(change['prev_geom_obj']) if change['diff_bbox']

      @@log.debug "#{change['el_type']} #{change['el_id']} (#{change['el_version']})"
      create_change_tiles(changeset_id, change, change['id'].to_i, zoom)
    end

    @tiles.each do |tile, data|
      @conn.exec_prepared('insert_tile', [changeset_id, data[:tstamp], tile[2], tile[0], tile[1],
          data[:changes].to_s.gsub("[", "{").gsub("]", "}"),
          to_postgres_geom_array(data[:geom]), to_postgres_geom_array(data[:prev_geom])])
    end

    @@log.debug "Aggregating tiles..."

    # Now generate tiles at lower zoom levels.
    (12..16).reverse_each do |i|
      @conn.exec("SELECT OWL_AggregateChangeset(#{changeset_id}, #{i}, #{i - 1})")
    end

    @tiles.size
  end

  def add_change_tile(x, y, zoom, change, geom, prev_geom)
    if !@tiles.include?([x, y, zoom])
      @tiles[[x, y, zoom]] = {
        :changes => [change['id'].to_i],
        :tstamp => change['tstamp'],
        :geom => [(geom ? @wkb_writer.write_hex(geom) : nil)],
        :prev_geom => [(prev_geom ? @wkb_writer.write_hex(prev_geom) : nil)]
      }
      return
    end

    @tiles[[x, y, zoom]][:changes] << change['id'].to_i
    @tiles[[x, y, zoom]][:geom] << (geom ? @wkb_writer.write_hex(geom) : nil)
    @tiles[[x, y, zoom]][:prev_geom] << (prev_geom ? @wkb_writer.write_hex(prev_geom) : nil)
  end

  def create_change_tiles(changeset_id, change, change_id, zoom)
    if change['el_action'] == 'DELETE'
      count = create_geom_tiles(changeset_id, change, change['prev_geom_obj'], change_id, zoom, true)
    else
      count = create_geom_tiles(changeset_id, change, change['geom_obj'], change_id, zoom, false)
      if change['geom_changed']
        count += create_geom_tiles(changeset_id, change, change['prev_geom_obj'], change_id, zoom, true)
      end
    end

    @@log.debug "  Created #{count} tile(s)"
  end

  def create_geom_tiles(changeset_id, change, geom, change_id, zoom, is_prev)
    return 0 if geom.nil?

    if change['diff_bbox']
      bbox_to_use = 'diff_bbox'
    else
      bbox_to_use = (is_prev ? 'prev_geom' : 'geom') + '_bbox'
    end

    bbox = box2d_to_bbox(change[bbox_to_use])
    tile_count = bbox_tile_count(zoom, bbox)

    @@log.debug "  tile_count = #{tile_count} (using #{bbox_to_use})"

    if change['el_type'] == 'N'
      # Fast track a change that fits on a single tile (e.g. all nodes) - just create the tile.
      tiles = bbox_to_tiles(zoom, bbox)
      add_change_tile(tiles.to_a[0][0], tiles.to_a[0][1], zoom, change, is_prev ? nil : geom, is_prev ? geom : nil)
      return 1
    elsif tile_count < 64
      # Does not make sense to try to reduce small geoms.
      tiles = bbox_to_tiles(zoom, bbox)
    else
      tiles_to_check = (tile_count < 2048 ? bbox_to_tiles(14, bbox) : prepare_tiles_to_check(geom, bbox, 14))
      @@log.debug "  tiles_to_check = #{tiles_to_check.size}"
      tiles = prepare_tiles(tiles_to_check, geom, 14, zoom)
    end

    @@log.debug "  Processing #{tiles.size} tile(s)..."

    test_geom = change['diff_geom_obj'] || geom
    count = 0

    for tile in tiles
      x, y = tile[0], tile[1]
      tile_geom = tile_geom(x, y, zoom)
      tile_geom.srid = 4326

      if test_geom.intersects?(tile_geom)
        intersection = geom.intersection(tile_geom)
        intersection.srid = 4326
        add_change_tile(x, y, zoom, change, is_prev ? nil : intersection, is_prev ? intersection : nil)
        count += 1
      end
    end
    count
  end

  def prepare_tiles(tiles_to_check, geom, source_zoom, zoom)
    tiles = Set.new
    for tile in tiles_to_check
      tile_geom = tile_geom(tile[0], tile[1], source_zoom)
      intersects = tile_geom.intersects?(geom)
      tiles.merge(subtiles(tile, source_zoom, zoom)) if intersects
    end
    tiles
  end

  def prepare_tiles_to_check(geom, bbox, source_zoom)
    tiles = Set.new
    test_zoom = 11
    bbox_to_tiles(test_zoom, bbox).select {|tile| geom.intersects?(tile_geom(tile[0], tile[1], test_zoom))}.each do |tile|
      tiles.merge(subtiles(tile, test_zoom, source_zoom))
    end
    tiles
  end

  def tile_geom(x, y, zoom)
    lat1, lon1 = tile2latlon(x, y, zoom)
    lat2, lon2 = tile2latlon(x + 1, y + 1, zoom)
    @wkt_reader.read("MULTIPOINT(#{lon1} #{lat1},#{lon2} #{lat2})").envelope
  end

  def generate_changes(changeset_id)
    @conn.exec("DELETE FROM changes WHERE changeset_id = #{changeset_id}")
    @conn.exec("INSERT INTO changes
      (changeset_id, tstamp, el_changeset_id, el_type, el_id, el_version, el_action,
        geom_changed, tags_changed, nodes_changed,
        members_changed, geom, prev_geom, tags, prev_tags, nodes, prev_nodes)
      SELECT * FROM OWL_GenerateChanges(#{changeset_id})")
  end

  def setup_prepared_statements
    @conn.prepare('select_changes',
      "SELECT id, el_action, el_id, el_version, el_type, tstamp, geom, prev_geom, geom_changed,
          CASE WHEN el_type = 'N' THEN ST_X(prev_geom) ELSE NULL END AS prev_lon,
          CASE WHEN el_type = 'N' THEN ST_Y(prev_geom) ELSE NULL END AS prev_lat,
          CASE WHEN el_type = 'N' THEN ST_X(geom) ELSE NULL END AS lon,
          CASE WHEN el_type = 'N' THEN ST_Y(geom) ELSE NULL END AS lat,
          Box2D(geom) AS geom_bbox, Box2D(prev_geom) AS prev_geom_bbox,
          Box2D(ST_Difference(geom, prev_geom)) AS diff_bbox
        FROM changes WHERE changeset_id = $1")

    @conn.prepare('insert_tile',
      "INSERT INTO tiles (changeset_id, tstamp, zoom, x, y, changes, geom, prev_geom) VALUES
        ($1, $2, $3, $4, $5, $6::bigint[],
        $7::geometry(GEOMETRY, 4326)[], $8::geometry(GEOMETRY, 4326)[])")
  end
end

end
