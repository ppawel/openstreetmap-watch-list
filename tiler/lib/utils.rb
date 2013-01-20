require 'set'

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
def tile2latlon(xtile, ytile, zoom)
  n = 2.0 ** zoom
  lon_deg = xtile / n * 360.0 - 180.0
  lat_rad = Math.atan(Math.sinh(Math::PI * (1 - 2 * ytile / n.to_f)))
  lat_deg = degrees(lat_rad)
  return lat_deg, lon_deg
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
  eval(str.gsub('{', '[\'').gsub('}', '\']').gsub(':', '\',\''))
end

def to_postgres_geom_array(geom_arr)
  str = ''
  geom_arr.each_with_index do |geom, index|
    str += ':' if index > 0
    if geom.nil?
      str += 'NULL'
      next
    end
    str += "#{geom}"
  end
  "{#{str}}"
end
