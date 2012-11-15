require 'logging'
require 'utils'

module Tiler

# Implements tiling logic.
class Tiler
  include ::Tiler::Logger

  attr_accessor :conn

  def initialize(conn)
    @conn = conn
    @conn.exec('CREATE TEMPORARY TABLE _way_geom (geom geometry, tstamp timestamp without time zone);')
    @conn.exec('CREATE TEMPORARY TABLE _tile_bboxes (x int, y int, zoom int, tile_bbox geometry);')
    @conn.exec('CREATE TEMPORARY TABLE _tile_changes_tmp (el_type element_type NOT NULL, tstamp timestamp without time zone,
      x int, y int, zoom int, tile_geom geometry);')
  end

  ##
  # Generates tiles for given zoom and changeset.
  #
  def generate(zoom, changeset_id, options = {})
    @conn.exec('TRUNCATE _tile_changes_tmp')

    process_node_changes(changeset_id, zoom)
    process_way_changes(changeset_id, zoom, options)

    # The following is a hack because of http://trac.osgeo.org/geos/ticket/600
    # First, try ST_Union (which will result in a simpler tile geometry), if that fails, go with ST_Collect.
    begin
      @conn.query("INSERT INTO changeset_tiles (changeset_id, tstamp, zoom, x, y, geom)
        SELECT  #{changeset_id}, MAX(tstamp) AS tstamp, zoom, x, y, ST_Union(tile_geom)
        FROM _tile_changes_tmp tmp
        WHERE NOT ST_IsEmpty(tile_geom)
        GROUP BY zoom, x, y").cmd_tuples
    rescue
      @@log.debug "Failed to create tile geometry with ST_Union, let's do ST_Collect..."
      @conn.query("INSERT INTO changeset_tiles (changeset_id, tstamp, zoom, x, y, geom)
        SELECT  #{changeset_id}, MAX(tstamp) AS tstamp, zoom, x, y, ST_Collect(tile_geom)
        FROM _tile_changes_tmp tmp
        WHERE NOT ST_IsEmpty(tile_geom)
        GROUP BY zoom, x, y").cmd_tuples
    end
  end

  ##
  # Retrieves a list of changeset ids according to given options. If --retile option is NOT specified then
  # changesets that already have tiles in the database are skipped.
  #
  def get_changeset_ids(options)
    if options[:changesets] == ['all']
      sql = "(SELECT id FROM changesets ORDER BY created_at DESC)"

      unless options[:retile]
        # We are NOT retiling so skip changesets that have been already tiled.
        sql += " EXCEPT SELECT changeset_id FROM changeset_tiles GROUP BY changeset_id"
      end

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
    count = @conn.query("DELETE FROM changeset_tiles WHERE changeset_id = #{changeset_id} AND zoom = #{zoom}").cmd_tuples
    @@log.debug "Removed existing tiles: #{count}"
    count
  end

  protected

  def process_node_changes(changeset_id, zoom)
    for change in get_node_changes(changeset_id)
      if change['current_lat']
        tile = latlon2tile(change['current_lat'].to_f, change['current_lon'].to_f, zoom)
        @conn.query("INSERT INTO _tile_changes_tmp (el_type, zoom, x, y, tile_geom) VALUES
          ('N', #{zoom}, #{tile[0]}, #{tile[1]},
          ST_SetSRID(ST_GeomFromText('POINT(#{change['current_lon']} #{change['current_lat']})'), 4326))")
      end

      if change['new_lat']
        tile = latlon2tile(change['new_lat'].to_f, change['new_lon'].to_f, zoom)
        @conn.query("INSERT INTO _tile_changes_tmp (el_type, zoom, x, y, tile_geom) VALUES
          ('N', #{zoom}, #{tile[0]}, #{tile[1]},
          ST_SetSRID(ST_GeomFromText('POINT(#{change['new_lon']} #{change['new_lat']})'), 4326))")
      end
    end
  end

  def process_way_changes(changeset_id, zoom, options)
    for change in get_way_changes(changeset_id)
      process_way_change(changeset_id, change, zoom, options) unless change['both_bbox'].nil?
    end
  end

  def process_way_change(changeset_id, change, zoom, options)
    @conn.exec('TRUNCATE _tile_bboxes')
    @conn.exec('TRUNCATE _way_geom')
    @conn.query("INSERT INTO _way_geom (geom, tstamp)
      SELECT
        CASE
          WHEN current_geom IS NOT NULL AND new_geom IS NOT NULL THEN
            ST_Union(current_geom, new_geom)
          WHEN current_geom IS NOT NULL THEN current_geom
          WHEN new_geom IS NOT NULL THEN new_geom
        END, tstamp
      FROM changes WHERE id = #{change['id']}")

    tiles = bbox_to_tiles(zoom, box2d_to_bbox(change["both_bbox"]))

    @@log.debug "Change #{change['id']}: Way #{change['el_id']} (#{change['version']}): processing #{tiles.size} tile(s)..."

    # Does not make sense to reduce small changesets.
    if tiles.size > 64
      size_before = tiles.size
      reduce_tiles(tiles, changeset_id, change, zoom)
      @@log.debug "Change #{change['id']}: Way #{change['el_id']} (#{change['version']}): reduced tiles: #{size_before} -> #{tiles.size}"
    end

    for tile in tiles
      x, y = tile[0], tile[1]
      lat1, lon1 = tile2latlon(x, y, zoom)
      lat2, lon2 = tile2latlon(x + 1, y + 1, zoom)

      @conn.query("INSERT INTO _tile_bboxes VALUES (#{x}, #{y}, #{zoom},
        ST_SetSRID('BOX(#{lon1} #{lat1},#{lon2} #{lat2})'::box2d, 4326))")
    end

    count = @conn.query("INSERT INTO _tile_changes_tmp (el_type, tstamp, zoom, x, y, tile_geom)
      SELECT 'W', tstamp, bb.zoom, bb.x, bb.y, ST_Intersection(geom, bb.tile_bbox)
      FROM _tile_bboxes bb, _way_geom
      WHERE ST_Intersects(geom, bb.tile_bbox)").cmd_tuples

    @@log.debug "Change #{change['id']}: Way #{change['el_id']} (#{change['version']}): created #{count} tile(s)"
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
        if !intersects
          subtiles = subtiles(tile, source_zoom, zoom)
          tiles.subtract(subtiles)
        end
      end
    end
  end

  def get_node_changes(changeset_id)
    @conn.query("SELECT
        ST_X(current_geom) AS current_lon,
        ST_Y(current_geom) AS current_lat,
        ST_X(new_geom) AS new_lon,
        ST_Y(new_geom) AS new_lat
      FROM changes WHERE changeset_id = #{changeset_id} AND el_type = 'N'").to_a
  end

  def get_way_changes(changeset_id)
    @conn.query("SELECT id, el_id, version, Box2D(ST_Collect(current_geom, new_geom)) AS both_bbox
      FROM changes WHERE changeset_id = #{changeset_id} AND el_type = 'W'
      ORDER BY el_id").to_a
  end
end

end
