#include "osm/db/owl_diff/way.hpp"
#include "osm/db/owl_diff/node.hpp"
#include "osm/util/lcs.hpp"
#include <stdexcept>
#include <iostream>

using std::runtime_error;
using std::vector;
using std::set;
using std::cout;
using std::endl;
using boost::optional;
using osm::util::CompressedBitset;

namespace osm { namespace db { namespace owl_diff {

const char *way::type = "way";

way::way(const tags_t &a, const tags_t &t, const std::vector<id_t> &wn) 
  : element(a, t), way_nodes(wn) {
  tags_t::const_iterator itr = a.find("tiles");
  if ((itr != a.end()) && (!itr->second.empty())) {
    tiles_cache = CompressedBitset(itr->second);
  }
}

bool way::geom_is_different(const way &w) const {
  return way_nodes != w.way_nodes;
}

void way::tiles(tiler &t, osm::io::Database &d) const {
  if (tiles_cache) {
    tiler::tileset_t cached_tiles = tiles_cache->decompress();
    t.add_tileset(cached_tiles);

  } else {
    // get a new, empty tiler so that the tiles can be calculated
    // separately and cached.
    tiler *tt = t.empty_tiler();

    // a way covers all the lines joining its segments.
    vector<node> nodes;
    nodes.reserve(way_nodes.size());
    for (vector<id_t>::const_iterator itr = way_nodes.begin(); 
         itr != way_nodes.end(); ++itr) {
      if (node::db_exists(*itr, d)) {
        nodes.push_back(node::db_load(*itr, d));
      }
    }
    if (nodes.size() > 1) {
      tt->add_point(nodes[0]);
      for (size_t i = 1; i < nodes.size(); ++i) {
        tt->add_line_between(nodes[i-1], nodes[i]);
      }
    }

    // insert tiles back into the original tiler
    const tiler::tileset_t &my_tiles = tt->tiles();
    t.add_tileset(my_tiles);
    // and add them to the cache
    tiles_cache = CompressedBitset(my_tiles);
    
    delete tt;
  }
}

void way::diff_tiles(const way &w, tiler &t, osm::io::Database &d) const {
  // if tags changed then it's just the tiles covering the old and
  // new versions (which may be the same if only the tags changed).
  // if only geometry changed there's a more complex algorithm:
  //  - find the LCS between the old and new way nodes
  //  - for each LCS section, create linestrings starting one place
  //    before the section and ending one place after.
  //  - for each linestring in old and new versions, find the tiles
  //    covered by those segments.
  vector<id_t> lcs;
  util::lcs(way_nodes, w.way_nodes, lcs);

  if (way_nodes.size() > 0) mark_diff(lcs, t, d);
  if (w.way_nodes.size() > 0) w.mark_diff(lcs, t, d);
}

void
way::mark_diff(const vector<id_t> &lcs, tiler &t, osm::io::Database &d) const {
  // the LCS had better be less than or equal to the length of way nodes
  // or something has gone spectacularly wrong.
  assert(lcs.size() <= way_nodes.size());

  // find the sections of way_nodes which *don't* match the LCS
  size_t last_match = 0;
  bool match = false;
  vector<id_t>::const_iterator lcs_itr = lcs.begin();
  // it is possible that the LCS has no elements in it, meaning the entire
  // way should be marked.
  if (lcs.size() > 0) {
    for (size_t i = 0; i < way_nodes.size(); ++i) {
      if (*lcs_itr == way_nodes[i]) {
        if (!match) {
          // mark from last_match to i
          mark_segment(last_match, i, t, d);
          match = true;
        }

        last_match = i;
        ++lcs_itr;

      } else {
        match = false;
      }
    }
  }
  if (!match) {
    mark_segment(last_match, way_nodes.size() - 1, t, d);
  }
}

void
way::mark_segment(size_t i, size_t j, tiler &t, osm::io::Database &d) const {
  size_t n;

  // this doesn't work quite right - it just ignores deleted nodes in ways as
  // if they didn't exist. there's probably a better way of dealing with it.
  for (n = i; n < j; ++n) {
    if (node::db_exists(way_nodes[n], d)) {
      node a = node::db_load(way_nodes[n], d);
      t.add_point(a);
      break;
    }
  }

  if (n < j) {
    node a = node::db_load(way_nodes[n], d);
    for (; n < j; ++n) {
      if (node::db_exists(way_nodes[n+1], d)) {
        node b = node::db_load(way_nodes[n+1], d);
        t.add_line_between(a, b);
        a = b;
      }
    }
  }
}

bool 
way::db_exists(id_t i, osm::io::Database &d) {
  tags_t attrs, tags;
  vector<id_t> way_nodes;
  return d.way(i, attrs, way_nodes, tags);
}

way 
way::db_load(id_t i, osm::io::Database &d) {
  tags_t attrs, tags;
  vector<id_t> way_nodes;
  bool ok = d.way(i, attrs, way_nodes, tags);
  if (!ok) {
    throw runtime_error("Can't load way from database!");
  }
  return way(attrs, tags, way_nodes);
}

void 
way::db_save(const way &w, osm::db::OWLDatabase &d) {
  if (w.visible) {
    d.update_way(w.id, w.attrs, w.way_nodes, w.tags, w.tiles_cache);
  } else {
    d.delete_way(w.id);
  }
}

} } }
