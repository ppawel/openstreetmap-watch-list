#ifndef OSM_DB_OWL_DIFF_NODE_HPP
#define OSM_DB_OWL_DIFF_NODE_HPP

#include <vector>
#include <set>
#include "osm/types.hpp"
#include "osm/db/owl_database.hpp"
#include "osm/db/owl_diff/element.hpp"

namespace osm { namespace db { namespace owl_diff {

// pre-declaration of tiler, since tiler also references node.
struct tiler;
struct way;

struct node : public element {
  static const char *type;
  double lat, lon;

  node(const tags_t &a, const tags_t &t);
  bool geom_is_different(const node &n) const;
  tile_t tile() const;
  void tiles(tiler &t, osm::io::Database &d) const;
  void diff_tiles(const node &n, tiler &t, osm::io::ExtendedDatabase &d) const;

  static bool db_exists(id_t i, osm::io::Database &d);
  static node db_load(id_t i, osm::io::Database &d);
  static void db_save(const node &n, osm::db::OWLDatabase &d);

private:
  void tiles_in_way(const way &w, const node &n, tiler &t, osm::io::ExtendedDatabase &d) const;
};

} } }

#endif /* OSM_DB_OWL_DIFF_NODE_HPP */
