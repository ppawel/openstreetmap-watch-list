#include "osm/db/owl_diff/tiler.hpp"
#include "osm/util/quad_tile.hpp"

using std::set;
using namespace osm::util;

namespace osm { namespace db { namespace owl_diff {

tiler::tiler() {
}

tiler::~tiler() throw() {
}

void
tiler::add_point(const node &n) {
  tileset.insert(xy2tile(lon2x(n.lon), lat2y(n.lat)));
}

void
tiler::add_line_between(const node &a, const node &b) {
  const tile_t at = a.tile();
  const tile_t bt = b.tile();

  // special case for identity, as this is a highly likely case.
  if (at != bt) {
    unsigned int ax, ay, bx, by;
    tile2xy(at, ax, ay);
    tile2xy(bt, bx, by);

    // special cases for axis-aligned lines, as these can be computed
    // much more simply.
    if (ay == by) {
      const int dir = (ax > bx) ? -1 : 1;
      unsigned int x = ax; 
      do {
	x += dir;
	tileset.insert(xy2tile(x, ay));
      } while (x != bx);
    } else if (ax == bx) {
      const int dir = (ay > by) ? -1 : 1;
      unsigned int y = ay;
      do {
	y += dir;
	tileset.insert(xy2tile(ax, y));
      } while (y != by);
    } else {
      // TODO: there's got to be something better than this...
      double abs_lat = std::abs(a.lat - b.lat);
      double abs_lon = std::abs(a.lon - b.lon);
      double max_abs = std::max(abs_lon, abs_lat);
      int span = 100 * ceil(max_abs * SCALE / double(1u << 16));
      double scale = 1.0 / double(span);
      for (int i = 0; i <= span; ++i) {
	double lat = (a.lat - b.lat) * i * scale + b.lat;
	double lon = (a.lon - b.lon) * i * scale + b.lon;
	tileset.insert(xy2tile(lon2x(lon), lat2y(lat)));
      }
    }
  }
}

void
tiler::add_tileset(const tileset_t &t) {
  tileset.insert(t.begin(), t.end());
}

tiler *
tiler::empty_tiler() const {
  return new tiler();
}

const tiler::tileset_t &
tiler::tiles() const {
  return tileset;
}

} } }
