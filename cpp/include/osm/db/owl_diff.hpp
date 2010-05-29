#ifndef OSM_DB_OWL_DIFF_HPP
#define OSM_DB_OWL_DIFF_HPP

#include <pqxx/pqxx>
#include <osm/io/diff.hpp>
#include <osm/db/owl_database.hpp>
#include <boost/noncopyable.hpp>
#include <map>
#include <string>

namespace osm { namespace db {

class OWLDiff
  : public io::Diff,
    public boost::noncopyable {
public:
  enum Mode { DebugMode, NormalMode };

private:
  //pqxx::work transaction;
  OWLDatabase &database;
  Mode mode;
  io::Diff::Action current_action;
  owl_diff::change_list all_changes;
  // map the user ID to the user name so we can keep an up-to-date mappings of the user names.
  std::map<id_t, std::string> users_seen; 
  // map changeset IDs to user IDs so we can keep up-to-date changeset details. this should be
  // taken out when (if?) changeset changes are included in the replication diffs.
  std::map<id_t, id_t> changesets_seen;

public:
  OWLDiff(OWLDatabase &db, Mode m);
  ~OWLDiff() throw();

  void finish();

  void node(const tags_t &attrs, const tags_t &tags);
  void way(const tags_t &attrs, const std::vector<id_t> &way_nodes, const tags_t &tags);
  void relation(const tags_t &attrs, const std::list<member> &members, const tags_t &tags);
  void set_current_action(io::Diff::Action);

  const owl_diff::change_list &changes_list() const;

private:
  void update_metadata(const tags_t &attrs);
};

} }

#endif /* OSM_DB_OWL_DIFF_HPP */
