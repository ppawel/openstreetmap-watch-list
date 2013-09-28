require 'ffi-geos'

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


def envelope_to_bbox(envelope)
  return nil if not envelope.is_a?(Geos::Polygon)
  ring = envelope.exterior_ring
  [ring[0].x, ring[0].y, ring[2].x, ring[2].y]
end
