require 'logging'
require 'utils'

module Tiler

# Implements tiling logic.
class Tiler
  include ::Tiler::Logger

  attr_accessor :conn

  def initialize(conn)
    @conn = conn
    @conn.exec('CREATE TEMPORARY TABLE _tile_bboxes (x int, y int, zoom int, tile_bbox geometry);')
    @conn.exec('CREATE TEMPORARY TABLE _tile_changes_tmp (x int, y int, zoom int, tile_geom geometry);')
  end

  def generate(zoom, changeset_id, options = {})
    @conn.exec('TRUNCATE _tile_changes_tmp')

    process_node_changes(changeset_id, zoom)
    process_way_changes(changeset_id, zoom)

    @conn.query("INSERT INTO changeset_tiles (changeset_id, zoom, x, y, geom)
      SELECT #{changeset_id}, zoom, x, y, ST_Collect(ST_MakeValid(tile_geom))
      FROM _tile_changes_tmp tmp
      WHERE NOT ST_IsEmpty(tile_geom)
      GROUP BY zoom, x, y").cmd_tuples
  end

  ##
  # Retrieves a list of changeset ids according to given options.
  #
  def get_changeset_ids(options)
    if options[:changesets] == ['all']
      sql = "(
        SELECT cs.id
        FROM changesets cs
        INNER JOIN changes c ON (c.changeset_id = cs.id)
        WHERE num_changes < #{options[:processing_change_limit]} AND
          c.current_geom IS NOT NULL OR c.new_geom IS NOT NULL
        GROUP BY cs.id, cs.created_at
        ORDER BY created_at DESC)"

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

  def clear_tiles(changeset_id, zoom)
    @conn.query("DELETE FROM changeset_tiles WHERE changeset_id = #{changeset_id} AND zoom = #{zoom}").cmd_tuples
  end

  protected

  def process_node_changes(changeset_id, zoom)
    for change in get_node_changes(changeset_id)
      if change['current_lat']
        tile = latlon2tile(change['current_lat'].to_f, change['current_lon'].to_f, zoom)
        @conn.query("INSERT INTO _tile_changes_tmp (zoom, x, y, tile_geom) VALUES
          (#{zoom}, #{tile[0]}, #{tile[1]},
          ST_SetSRID(ST_GeomFromText('POINT(#{change['current_lon']} #{change['current_lat']})'), 4326))")
      end

      if change['new_lat']
        tile = latlon2tile(change['new_lat'].to_f, change['new_lon'].to_f, zoom)
        @conn.query("INSERT INTO _tile_changes_tmp (zoom, x, y, tile_geom) VALUES
          (#{zoom}, #{tile[0]}, #{tile[1]},
          ST_SetSRID(ST_GeomFromText('POINT(#{change['new_lon']} #{change['new_lat']})'), 4326))")
      end
    end
  end

  def process_way_changes(changeset_id, zoom)
    for change in get_way_changes(changeset_id)
      process_way_change(changeset_id, change, 'current', zoom) unless change['current_bbox'].nil?
      process_way_change(changeset_id, change, 'new', zoom) unless change['new_bbox'].nil?
    end
  end

  def process_way_change(changeset_id, change, geom_type, zoom)
    @conn.exec('TRUNCATE _tile_bboxes')

    tiles = bbox_to_tiles(zoom, box2d_to_bbox(change["#{geom_type}_bbox"]))

    for tile in tiles
      x, y = tile[0], tile[1]
      lat1, lon1 = tile2latlon(x, y, zoom)
      lat2, lon2 = tile2latlon(x + 1, y + 1, zoom)

      @conn.query("INSERT INTO _tile_bboxes VALUES (#{x}, #{y}, #{zoom},
        ST_SetSRID('BOX(#{lon1} #{lat1},#{lon2} #{lat2})'::box2d, 4326))")
    end

    @@log.debug "Way #{change['el_id']}: processing #{tiles.size} tile(s) [#{geom_type}]"

    count = @conn.query("INSERT INTO _tile_changes_tmp (zoom, x, y, tile_geom)
      SELECT bb.zoom, bb.x, bb.y, ST_Intersection(ST_MakeValid(#{geom_type}_geom::geometry), bb.tile_bbox)::geometry
      FROM _tile_bboxes bb
      INNER JOIN changes cs ON ST_Intersects(#{geom_type}_geom, bb.tile_bbox)
      WHERE cs.id = #{change['id']}").cmd_tuples

    @@log.debug "Way #{change['el_id']}: created #{count} tile(s) [#{geom_type}]"
  end

  def get_node_changes(changeset_id)
    @conn.query("SELECT
        ST_X(current_geom::geometry) AS current_lon,
        ST_Y(current_geom::geometry) AS current_lat,
        ST_X(new_geom::geometry) AS new_lon,
        ST_Y(new_geom::geometry) AS new_lat
      FROM changes WHERE changeset_id = #{changeset_id} AND el_type = 'N'").to_a
  end

  def get_way_changes(changeset_id)
    @conn.query("SELECT
        id,
        el_id,
        Box2D(current_geom::geometry) AS current_bbox,
        Box2D(new_geom::geometry) AS new_bbox
        FROM changes
        WHERE changeset_id = #{changeset_id} AND el_type = 'W'").to_a
  end
end

end
