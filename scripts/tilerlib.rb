def degrees(rad)
  rad * 180 / Math::PI
end

def radians(angle)
  angle / 180 * Math::PI
end

# Translated to Ruby rom http://wiki.openstreetmap.org/wiki/Slippy_map_tilenames
def latlon2tile(lat_deg, lon_deg, zoom)
  lat_rad = radians(lat_deg)
  n = 2.0 ** zoom
  xtile = ((lon_deg + 180.0) / 360.0 * n).floor
  ytile = ((1.0 - Math.log(Math.tan(lat_rad) + 1.0 / Math.cos(lat_rad)) / Math::PI) / 2.0 * n).floor
  return xtile, ytile
end

# Translated to Ruby rom http://wiki.openstreetmap.org/wiki/Slippy_map_tilenames
def tile2latlon(xtile, ytile, zoom)
  n = 2.0 ** zoom
  lon_deg = xtile / n * 360.0 - 180.0
  lat_rad = Math.atan(Math.sinh(Math::PI * (1 - 2 * ytile / n.to_f)))
  lat_deg = degrees(lat_rad)
  return lat_deg, lon_deg
end

# Implements tiling logic.
class Tiler
  attr_accessor :conn

  def initialize(conn)
    @conn = conn
  end

  def generate(zoom, changeset_id)
    removed_count = clear_tiles(changeset_id, zoom)
    puts "    Removed existing tiles: #{removed_count}"

    bbox = changeset_bbox(changeset_id)
    puts "    bbox = #{bbox}"

    count = 0
    tiles = bbox_to_tiles(zoom, bbox)

    puts "    Tiles to process: #{tiles.size}"

    tiles.each do |tile|
      x, y = tile[0], tile[1]
      lat1, lon1 =  tile2latlon(x, y, zoom)
      lat2, lon2 =  tile2latlon(x + 1, y + 1, zoom)

      geom = @conn.query("
        SELECT ST_Intersection(
          geom::geometry,
          ST_SetSRID(ST_MakeBox2D(ST_MakePoint(#{lon2}, #{lat1}), ST_MakePoint(#{lon1}, #{lat2})), 4326))
        FROM changesets WHERE id = #{changeset_id}").getvalue(0, 0)

      if geom != '0107000020E610000000000000' and geom
        puts "    Got geometry for tile (#{x}, #{y})"
        @conn.query("INSERT INTO changeset_tiles (changeset_id, zoom, x, y, geom)
          VALUES (#{changeset_id}, #{zoom}, #{x}, #{y}, '#{geom}')")
        count += 1
      end
    end

    count
  end

  protected

  def clear_tiles(changeset_id, zoom)
    @conn.query("DELETE FROM changeset_tiles WHERE changeset_id = #{changeset_id} AND zoom = #{zoom}").cmd_tuples
  end

  def bbox_to_tiles(zoom, bbox)
    tiles = []
    top_left = latlon2tile(bbox['xmin'], bbox['ymin'], zoom)
    bottom_right = latlon2tile(bbox['xmax'], bbox['ymax'], zoom)
    min_y = [top_left[1], bottom_right[1]].min
    max_y = [top_left[1], bottom_right[1]].max

    (top_left[0]..bottom_right[0]).each do |x|
      (min_y..max_y).each do |y|
        tiles << [x, y]
      end
    end

    tiles
  end

  def changeset_bbox(changeset_id)
    result = @conn.query("SELECT ST_XMin(geom::geometry) AS ymin, ST_XMax(geom::geometry) AS ymax,
      ST_YMin(geom::geometry) AS xmin, ST_YMax(geom::geometry) AS xmax
      FROM changesets WHERE id = #{changeset_id}")
    row = result.to_a[0]
    row.merge(row) {|k, v| v.to_f}
  end
end
