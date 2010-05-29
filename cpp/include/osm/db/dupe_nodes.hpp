#ifndef OSM_DB_DUPE_NODES_HPP
#define OSM_DB_DUPE_NODES_HPP

#include "osm/db/owl_diff/change.hpp"
#include <pqxx/pqxx>
#include <set>
#include <map>

namespace osm { namespace db {

class DupeNodes 
  : public pqxx::transactor<pqxx::work> {
private:
  struct cs_info {
    id_t changeset, uid;
    cs_info(id_t cs, id_t u) : changeset(cs), uid(u) {}
  };

  // the list of tile IDs to update.
  std::map<tile_t, cs_info> tiles;

public:

  // construct from a bunch of changes by selecting out the ones which matter.
  DupeNodes(const owl_diff::change_list &c);

  // construct from a set of tile_ids
  DupeNodes(const std::set<tile_t> &t);

  // prepares the connection (sets up prepared queries on the connection).
  void prepare(pqxx::connection &conn);

  // executes the transaction.
  void operator()(pqxx::work &tx);

};

} }

#endif /* OSM_DB_DUPE_NODES_HPP */
