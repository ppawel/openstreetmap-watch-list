#ifndef OSM_DB_OWL_LOADER_HPP
#define OSM_DB_OWL_LOADER_HPP

#include <osm/io/document.hpp>
#include <pqxx/pqxx>
#include <boost/array.hpp>

namespace osm { namespace db {

/**
 * fast loader for OWL data. postgres has a faster path for bulk loading data 
 * using the COPY command.
 */
class OWLLoader 
  : public io::Document {
private:
  pqxx::work transaction;

  // trying to make the import process more efficient by buffering up a
  // bunch of data and doing the tablewriter import on chunks, rather 
  // than using multiple connections and multiple transactions.
  std::vector<boost::array<int64_t, 6> > nodes_buffer;
  std::vector<boost::array<id_t, 3> > ways_buffer, relations_buffer, way_nodes_buffer;
  std::vector<boost::array<std::string, 3> > node_tags_buffer, way_tags_buffer, relation_tags_buffer;
  std::vector<boost::array<std::string, 5> > relation_members_buffer;

public:
  OWLLoader(pqxx::connection &c, size_t buffer_size);
  virtual ~OWLLoader() throw();

  // call this when the loader should expect no more elements.
  void finish();

  void node(const tags_t &attrs, const tags_t &tags);
  void way(const tags_t &attrs, const std::vector<id_t> &way_nodes, const tags_t &tags);
  void relation(const tags_t &attrs, const std::list<member> &members, const tags_t &tags);

private:
  void push_node(int id, int version, int changeset, int lat, int lon);
  void push_way(id_t id, id_t version, id_t changeset);
  void push_relation(id_t id, id_t version, id_t changeset);
  void push_node_tag(const std::string &id, const std::string &k, const std::string &v);
  void push_way_tag(const std::string &id, const std::string &k, const std::string &v);
  void push_relation_tag(const std::string &id, const std::string &k, const std::string &v);
  void push_way_node(id_t id, id_t node_id, id_t seq);
  void push_relation_member(const std::string &id, const std::string &m_role, const std::string &m_type, const std::string &m_id, const std::string &seq);

  OWLLoader(const OWLLoader &); //< can't copy-construct this class or they'd share a transaction
};

} }

#endif /* OSM_DB_OWL_LOADER_HPP */
