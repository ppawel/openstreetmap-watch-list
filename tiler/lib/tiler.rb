require 'logging'
require 'utils'

module Tiler

# Implements tiling logic.
class Tiler
  include ::Tiler::Logger

  attr_accessor :conn

  def initialize(conn)
    @conn = conn
  end

  def generate(zoom, changeset_id, options = {})
    if options[:retile]
      removed_count = clear_tiles(changeset_id, zoom)
      @@log.debug "Removed existing tiles: #{removed_count}"
      process = true
    else
      existing_tiles = get_existing_tiles(changeset_id, zoom)
      @@log.debug "Existing tiles: #{existing_tiles.size}"
      return existing_tiles.size if !existing_tiles.empty?
    end

    bbox = changeset_bbox(changeset_id)
    @@log.debug "bbox = #{bbox}"

    count = 0
    tiles = bbox_to_tiles(zoom, bbox)

    @@log.debug "Tiles to process: #{tiles.size}"

    #if tiles.size > 256
      tiles = reduced_tiles(changeset_id, zoom)
      @@log.debug "Tiles to process (reduced): #{tiles.size}"
    #end

    tiles.each do |tile|
      x, y = tile[0], tile[1]
      lat1, lon1 = tile2latlon(x, y, zoom)
      lat2, lon2 = tile2latlon(x + 1, y + 1, zoom)

      geom = @conn.query("
        SELECT ST_Intersection(
          geom,
          ST_SetSRID(ST_MakeBox2D(ST_MakePoint(#{lon2}, #{lat1}), ST_MakePoint(#{lon1}, #{lat2})), 4326))
        FROM changesets WHERE id = #{changeset_id}").getvalue(0, 0)

      if geom != '0107000020E610000000000000' and geom
        @@log.debug "    Got geometry for tile (#{x}, #{y})"
        @conn.query("INSERT INTO changeset_tiles (changeset_id, zoom, x, y, geom)
          VALUES (#{changeset_id}, #{zoom}, #{x}, #{y}, '#{geom}')")
        count += 1
      end
    end

    count
  end

  def get_changeset_ids(options)
    ids = []
    if options[:changesets] == ['all']
      @conn.query("SELECT id FROM changesets ORDER BY created_at DESC").each {|row| ids << row['id'].to_i}
    else
      ids = options[:changesets]
    end
    ids
  end

  protected

  def reduced_tiles(changeset_id, zoom)
    tiles = []
    change_bboxes(changeset_id).collect {|bbox| tiles += bbox_to_tiles(zoom, bbox)}
    tiles.uniq
  end

  def get_existing_tiles(changeset_id, zoom)
    tiles = []
    @conn.query("SELECT x, y
        FROM changeset_tiles WHERE changeset_id = #{changeset_id} AND zoom = #{zoom}").to_a.each do |row|
      tiles << [row['x'].to_i, row['y'].to_i]
    end
    tiles
  end

  def clear_tiles(changeset_id, zoom)
    @conn.query("DELETE FROM changeset_tiles WHERE changeset_id = #{changeset_id} AND zoom = #{zoom}").cmd_tuples
  end

  def changeset_bbox(changeset_id)
    result = @conn.query("SELECT ST_XMin(geom::geometry) AS ymin, ST_XMax(geom::geometry) AS ymax,
      ST_YMin(geom::geometry) AS xmin, ST_YMax(geom::geometry) AS xmax
      FROM changesets WHERE id = #{changeset_id}")
    row = result.to_a[0]
    row.merge(row) {|k, v| v.to_f}
  end

  def change_bboxes(changeset_id)
    bboxes = []
    @conn.query("SELECT ST_XMin(current_geom::geometry) AS ymin, ST_XMax(current_geom::geometry) AS ymax,
        ST_YMin(current_geom::geometry) AS xmin, ST_YMax(current_geom::geometry) AS xmax
        FROM changes WHERE changeset_id = #{changeset_id}
          UNION
        SELECT ST_XMin(new_geom::geometry) AS ymin, ST_XMax(new_geom::geometry) AS ymax,
        ST_YMin(new_geom::geometry) AS xmin, ST_YMax(new_geom::geometry) AS xmax
        FROM changes WHERE changeset_id = #{changeset_id}").to_a.each do |row|
      bboxes << row.merge(row) {|k, v| v.to_f}
    end
    bboxes
  end
end

end
