#ifndef OSM_DB_OWL_DIFF_WAY_HPP
#define OSM_DB_OWL_DIFF_WAY_HPP

#include <vector>
#include <set>
#include <boost/optional.hpp>

#include "osm/types.hpp"
#include "osm/db/owl_database.hpp"
#include "osm/db/owl_diff/tiler.hpp"
#include "osm/db/owl_diff/element.hpp"
#include "osm/util/compressed_bitset.hpp"

namespace osm { namespace db { namespace owl_diff {

struct way : public element {
  static const char *type;
  std::vector<id_t> way_nodes;
  // if present, caches the tile footprint of the way
  mutable boost::optional<util::CompressedBitset> tiles_cache;
  
  way(const tags_t &a, const tags_t &t, const std::vector<id_t> &wn);
  bool geom_is_different(const way &w) const;
  void tiles(tiler &t, osm::io::Database &d) const;
  void diff_tiles(const way &w, tiler &t, osm::io::Database &d) const;

  static bool db_exists(id_t i, osm::io::Database &d);
  static way db_load(id_t i, osm::io::Database &d);
  static void db_save(const way &w, osm::db::OWLDatabase &d);

private:
  void mark_diff(const std::vector<id_t> &lcs, tiler &t, osm::io::Database &d) const;
  void mark_segment(size_t i, size_t j, tiler &t, osm::io::Database &d) const;
};

} } }

#endif /* OSM_DB_OWL_DIFF_WAY_HPP */
