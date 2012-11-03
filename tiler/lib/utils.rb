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

  tiles.uniq
end
