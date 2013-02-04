require 'set'
require 'ffi-geos'

def degrees(rad)
  rad * 180 / Math::PI
end

def radians(angle)
  angle / 180 * Math::PI
end

# Translated to Ruby rom http://wiki.openstreetmap.org/wiki/Slippy_map_tilenames
def latlon2tile(lat_deg, lon_deg, zoom)
  lat_deg = -89.999999 if lat_deg == -90.0 # Hack
  lat_rad = radians(lat_deg)
  n = 2.0 ** zoom
  xtile = ((lon_deg + 180.0) / 360.0 * n).floor
  ytile = ((1.0 - Math.log(Math.tan(lat_rad) + 1.0 / Math.cos(lat_rad)) / Math::PI) / 2.0 * n).floor
  return xtile, ytile
end

# Translated to Ruby rom http://wiki.openstreetmap.org/wiki/Slippy_map_tilenames
def tile2latlon(x, y, zoom)
  n = 2.0 ** zoom
  lon_deg = x / n * 360.0 - 180.0
  lat_rad = Math.atan(Math.sinh(Math::PI * (1 - 2 * y / n.to_f)))
  lat_deg = degrees(lat_rad)
  return lat_deg, lon_deg
end

def tile2bbox(x, y, zoom)
  lat1, lon1 = tile2latlon(x, y, zoom)
  lat2, lon2 = tile2latlon(x + 1, y + 1, zoom)
  [lon1, lat1, lon2, lat2]
end

##
# Converts PostGIS' BOX2D string representation to a list.
#
def box2d_to_bbox(box2d)
  box2d.gsub(',', ' ').gsub('BOX(', '').gsub(')', '').split(' ').map(&:to_f)
end

##
# bbox is [xmin, ymin, xmax, ymax]
#
def bbox_to_tiles(zoom, bbox)
  tiles = Set.new
  top_left = latlon2tile(bbox[1], bbox[0], zoom)
  bottom_right = latlon2tile(bbox[3], bbox[2], zoom)
  min_y = [top_left[1], bottom_right[1]].min
  max_y = [top_left[1], bottom_right[1]].max
  (top_left[0]..bottom_right[0]).each do |x|
    (min_y..max_y).each do |y|
      tiles << [x, y]
    end
  end
  tiles
end

def envelope_to_bbox(envelope)
  return nil if not envelope.is_a?(Geos::Polygon)
  ring = envelope.exterior_ring
  [ring[0].x, ring[0].y, ring[2].x, ring[2].y]
end

def bbox_tile_count(zoom, bbox)
  tiles = Set.new
  top_left = latlon2tile(bbox[1], bbox[0], zoom)
  bottom_right = latlon2tile(bbox[3], bbox[2], zoom)
  min_y = [top_left[1], bottom_right[1]].min
  max_y = [top_left[1], bottom_right[1]].max
  (bottom_right[0] - top_left[0] + 1) * (max_y - min_y + 1)
end

def subtiles(tile, source_zoom, target_zoom)
  tiles = Set.new
  subtiles_per_tile = 2**target_zoom / 2**source_zoom
  (tile[0] * subtiles_per_tile..(tile[0] + 1) * subtiles_per_tile - 1).each do |x|
    (tile[1] * subtiles_per_tile..(tile[1] + 1) * subtiles_per_tile - 1).each do |y|
      tiles << [x, y]
    end
  end
  tiles
end

def pg_parse_array(str)
  eval(str.gsub('{', '[').gsub('}', ']'))
end

def pg_parse_geom_array(str)
  a = eval(str.gsub('{', '[\'').gsub('}', '\']').gsub(':', '\',\''))
  a.collect {|v| v == 'NULL' ? nil : v}
end

def to_postgres_geom_array(geom_arr)
  result = ''
  geom_arr.each_with_index do |geom, index|
    result << ':' if index > 0
    if geom.nil?
      result << 'NULL'
      next
    end
    result << geom
  end
  "{#{result}}"
end

def memory_usage
  `ps -o rss= -p #{$$}`.to_i
end

def get_tile_geom(x, y, zoom)
  cs = Geos::CoordinateSequence.new(5, 2)
  y1, x1 = tile2latlon(x, y, zoom)
  y2, x2 = tile2latlon(x + 1, y + 1, zoom)
  cs.y[0], cs.x[0] = y1, x1
  cs.y[1], cs.x[1] = y1, x2
  cs.y[2], cs.x[2] = y2, x2
  cs.y[3], cs.x[3] = y2, x1
  cs.y[4], cs.x[4] = y1, x1
  Geos::create_polygon(cs, :srid => 4326)
end

def prepare_tiles(tiles_to_check, geom, source_zoom, zoom)
  tiles = Set.new
  for tile in tiles_to_check
    tile_geom = get_tile_geom(tile[0], tile[1], source_zoom)
    intersects = geom.intersects?(tile_geom)
    tiles.merge(subtiles(tile, source_zoom, zoom)) if intersects
  end
  tiles
end

def prepare_tiles_to_check(geom, bbox, source_zoom)
  tiles = Set.new
  test_zoom = 11
  bbox_to_tiles(test_zoom, bbox).select {|tile| geom.intersects?(get_tile_geom(tile[0], tile[1], test_zoom))}.each do |tile|
    tiles.merge(subtiles(tile, test_zoom, source_zoom))
  end
  tiles
end
