#ifndef OSM_DB_OWL_DATABASE_HPP
#define OSM_DB_OWL_DATABASE_HPP

#include <osm/io/extended_database.hpp>
#include <osm/db/owl_diff/change.hpp>
#include <osm/util/compressed_bitset.hpp>
#include <pqxx/pqxx>
#include <boost/optional.hpp>

namespace osm { namespace db {

/**
 * contains all the database-specific logic for the OWL database format. should probably
 * be called "PGOWLDatabase", but there isn't a different backend at the moment.
 */
class OWLDatabase
  : public io::ExtendedDatabase {
private:
  pqxx::work transaction;

public:
  explicit OWLDatabase(pqxx::connection &c);

  ~OWLDatabase() throw();

  // to commit the changes to the database (if any)
  void finish();

  // getters
  bool node(id_t id, tags_t &attrs, tags_t &tags);
  bool way(id_t id, tags_t &attrs, std::vector<id_t> &way_nodes, tags_t &tags);
  bool relation(id_t id, tags_t &attrs, std::list<member> &members, tags_t &tags);

  // return way ids which contain the given node id
  std::vector<id_t> ways_using_node(id_t id);

  // setters
  void update_node(id_t id, const tags_t &attrs, const tags_t &tags);
  void update_way(id_t id, const tags_t &attrs, const std::vector<id_t> &way_nodes, const tags_t &tags, boost::optional<util::CompressedBitset> &bs);
  void update_relation(id_t id, const tags_t &attrs, const std::list<member> &members, const tags_t &tags);

  // deleters
  void delete_node(id_t id);
  void delete_way(id_t id);
  void delete_relation(id_t id);

  // stores a change (append-only)
  void insert_change(const owl_diff::change &c);

  // updates the users table
  void update_users(const std::map<id_t, std::string> &users);
  // updates changesets table (partially, a daemon does the rest)
  void update_changesets(const std::map<id_t, id_t> &changesets);
};

} } 

#endif /* OSM_DB_OWL_DATABASE_HPP */
