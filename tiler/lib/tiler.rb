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
  end

  ##
  # Generates tiles for given zoom and changeset.
  #
  def generate(zoom, changeset_id, options = {})
    tile_count = nil
    @conn.transaction do |c|
      @tiles = {}
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

    for change in @conn.exec("SELECT id, el_id, el_version, el_type, tstamp, geom, prev_geom, geom_changed,
          CASE WHEN el_type = 'N' THEN ST_X(prev_geom) ELSE NULL END AS prev_lon,
          CASE WHEN el_type = 'N' THEN ST_Y(prev_geom) ELSE NULL END AS prev_lat,
          CASE WHEN el_type = 'N' THEN ST_X(geom) ELSE NULL END AS lon,
          CASE WHEN el_type = 'N' THEN ST_Y(geom) ELSE NULL END AS lat,
          Box2D(geom) AS geom_bbox, Box2D(prev_geom) AS prev_geom_bbox
        FROM changes WHERE changeset_id = #{changeset_id}").to_a
      change['geom_changed'] = (change['geom_changed'] == 't')
      change['geom_obj'] = @wkb_reader.read_hex(change['geom']) if change['geom']
      change['prev_geom_obj'] = @wkb_reader.read_hex(change['prev_geom']) if change['prev_geom']

      @@log.debug "#{change['el_type']} #{change['el_id']} (#{change['el_version']})"
      create_change_tiles(changeset_id, change, change['id'].to_i, zoom)
    end

    @tiles.each do |tile, data|
      @conn.exec("INSERT INTO tiles (changeset_id, tstamp, zoom, x, y, changes, geom, prev_geom) VALUES (
        #{changeset_id}, '#{data[:tstamp]}', #{tile[2]}, #{tile[0]}, #{tile[1]},
          ARRAY#{data[:changes]}, #{to_postgres_geom_array(data[:geom])}, #{to_postgres_geom_array(data[:prev_geom])})")
    end

    @@log.debug "Aggregating tiles..."

    # Now generate tiles at lower zoom levels.
    (3..16).reverse_each do |i|
      @conn.exec("SELECT OWL_AggregateChangeset(#{changeset_id}, #{i}, #{i - 1})")
    end

    @tiles.size
  end

  def to_postgres_geom_array(geom_arr)
    str = ''
    geom_arr.each_with_index do |geom, index|
      str += ',' if index > 0
      if geom.nil?
        str += 'NULL'
        next
      end
      str += "ST_SetSRID('#{geom}'::geometry, 4326)"
    end
    str = "ARRAY[#{str}]"
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
    count = create_geom_tiles(changeset_id, change, change['geom_obj'], change_id, zoom, false)

    if change['geom_changed']
      count += create_geom_tiles(changeset_id, change, change['prev_geom_obj'], change_id, zoom, true)
    end

    @@log.debug "  Created #{count} tile(s)"
  end

  def create_geom_tiles(changeset_id, change, geom, change_id, zoom, is_prev)
    return 0 if geom.nil?

    bbox = box2d_to_bbox(change[(is_prev ? 'prev_geom' : 'geom') + '_bbox'])
    tile_count = bbox_tile_count(zoom, bbox)

    @@log.debug "  tile_count = #{tile_count}"

    if tile_count == 1
      tiles = bbox_to_tiles(zoom, bbox)
      add_change_tile(tiles.to_a[0][0], tiles.to_a[0][1], zoom, change, is_prev ? nil : geom, is_prev ? geom : nil)
      return 1
    elsif tile_count < 64
      # Does not make sense to try to reduce small geoms.
      tiles = bbox_to_tiles(zoom, bbox)
    else
      tiles = reduce_tiles(changeset_id, change, bbox, zoom)
    end

    @@log.debug "  Processing #{tiles.size} tile(s)..."

    count = 0

    for tile in tiles
      x, y = tile[0], tile[1]
      lat1, lon1 = tile2latlon(x, y, zoom)
      lat2, lon2 = tile2latlon(x + 1, y + 1, zoom)
      tile_geom = @wkt_reader.read("MULTIPOINT(#{lon1} #{lat1},#{lon2} #{lat2})").envelope

      if geom.intersects?(tile_geom)
        intersection = geom.intersection(tile_geom)
        add_change_tile(x, y, zoom, change, is_prev ? nil : intersection, is_prev ? intersection : nil)
        count += 1
      end
    end
    count
  end

  def reduce_tiles(changeset_id, change, bbox, zoom)
    tiles = Set.new
    for source_zoom in [14]
      for tile in bbox_to_tiles(source_zoom, bbox)
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
      (changeset_id, tstamp, el_changeset_id, el_type, el_id, el_version, el_action,
        geom_changed, tags_changed, nodes_changed,
        members_changed, geom, prev_geom, tags, prev_tags, nodes, prev_nodes)
      SELECT * FROM OWL_GenerateChanges(#{changeset_id})")
  end
end

end
