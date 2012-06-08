#include "osm/db/owl_diff/node.hpp"
#include "osm/db/owl_diff/way.hpp"
#include "osm/db/owl_diff/tiler.hpp"
#include "osm/db/owl_diff/attributes.hpp"
#include "osm/util/quad_tile.hpp"
#include <boost/lexical_cast.hpp>
#include <stdexcept>
#include <iostream>
#include <cmath>

using boost::lexical_cast;
using std::runtime_error;
using std::set;
using std::vector;
using std::cout;
using std::endl;

namespace osm { namespace db { namespace owl_diff {

#define LOC_PRECISION (0.5e-7)
// in degrees squared, so this is roughly a move of 5 degrees, which
// might not be so bad at the poles. we'll have to see if this needs
// changing in practice.
#define VERY_LONG_DISTANCE_SQUARED (25.0)

const char *node::type = "node";

node::node(const tags_t &a, const tags_t &t) 
  : element(a, t),
    lat(lexical_cast<double>(required_attribute(attrs, "lat"))),
    lon(lexical_cast<double>(required_attribute(attrs, "lon"))) {
}

bool node::geom_is_different(const node &n) const {
  return
    (abs(lat - n.lat) > LOC_PRECISION) || 
    (abs(lon - n.lon) > LOC_PRECISION);
}
  
tile_t node::tile() const {
  using namespace osm::util;
  return xy2tile(lon2x(lon), lat2y(lat));
}

void node::tiles(tiler &t, osm::io::Database &d) const {
  // tiles covered by a node are just the one intersecting the
  // lat/lon of the node itself.
  t.add_point(*this);
}

void node::diff_tiles(const node &n, tiler &t, osm::io::ExtendedDatabase &d) const {
  // tiles covered by a node diff are the old and new positions,
  unsigned int cur_tile = tile();
  unsigned int new_tile = n.tile();
  
  t.add_point(*this);
  if (cur_tile != new_tile) { t.add_point(n); }

  // if the node has moved very far, then don't count the ways it
  // was attached to, as this creates an absolutely huge set of 
  // tiles and isn't actually very useful to anyone.
  double dist = (lat - n.lat) * (lat - n.lat) + (lon - n.lon) * (lon - n.lon);
  if (dist < VERY_LONG_DISTANCE_SQUARED) {
    // plus the lines joining the old and new positions to any other
    // nodes connected by ways.
    vector<id_t> ways = d.ways_using_node(id);
    for (vector<id_t>::iterator itr = ways.begin();
         itr != ways.end(); ++itr) {
      if (way::db_exists(*itr, d)) {
        way w = way::db_load(*itr, d);
        tiles_in_way(w, n, t, d);
      }
    }

  } else {
    cout << "Warning: not evaluating tiles for ways using node " << id 
         << " at version " << version << " as distance moved is " 
         << std::sqrt(dist) << " degrees." << endl;
  }
}

void node::tiles_in_way(const way &w, const node &n, tiler &t, osm::io::ExtendedDatabase &d) const {
  vector<id_t>::const_iterator ntr = w.way_nodes.begin();

  const vector<id_t>::const_iterator end = w.way_nodes.end();
  while (ntr != end) {
    ntr = find(ntr, end, id);

    if (ntr == end) {
      break;
    }

    if ((ntr != w.way_nodes.begin()) && db_exists(*(ntr - 1), d)) {
      node m = db_load(*(ntr - 1), d);
      t.add_line_between(*this, m);
      t.add_line_between(n, m);
    }
    if ((ntr + 1 != end) && db_exists(*(ntr + 1), d)) {
      node m = db_load(*(ntr + 1), d);
      t.add_line_between(*this, m);
      t.add_line_between(n, m);
    }

    ++ntr;
  }
}

bool 
node::db_exists(id_t i, osm::io::Database &d) {
  tags_t attrs, tags;
  return d.node(i, attrs, tags);
}

node 
node::db_load(id_t i, osm::io::Database &d) {
  tags_t attrs, tags;
  bool ok = d.node(i, attrs, tags);
  if (!ok) {
    throw runtime_error("Can't load node from database!");
  }
  return node(attrs, tags);
}

void 
node::db_save(const node &n, osm::db::OWLDatabase &d) {
  if (n.visible) {
    d.update_node(n.id, n.attrs, n.tags);
  } else {
    d.delete_node(n.id);
  }
}

} } }
