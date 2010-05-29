#ifndef OSM_DB_OWL_DIFF_RELATION_HPP
#define OSM_DB_OWL_DIFF_RELATION_HPP

#include <list>
#include <set>
#include "osm/types.hpp"
#include "osm/member.hpp"
#include "osm/db/owl_database.hpp"
#include "osm/db/owl_diff/tiler.hpp"
#include "osm/db/owl_diff/element.hpp"

namespace osm { namespace db { namespace owl_diff {

struct relation : public element {
  static const char *type;
  std::list<member> members;
  
  relation(const tags_t &a, const tags_t &t, const std::list<member> &m);
  bool geom_is_different(const relation &r) const;
  void tiles(tiler &t, osm::io::Database &d) const;
  void diff_tiles(const relation &r, tiler &t, osm::io::Database &d) const;

  static bool db_exists(id_t i, osm::io::Database &d);
  static relation db_load(id_t i, osm::io::Database &d);
  static void db_save(const relation &r, osm::db::OWLDatabase &d);

private:
  void recursive_tiles(std::set<id_t> &ids, tiler &t, osm::io::Database &d) const;
};

} } }

#endif /* OSM_DB_OWL_DIFF_RELATION_HPP */
