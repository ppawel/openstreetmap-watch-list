#include <boost/lexical_cast.hpp>
#include <iostream>

#include "osm/db/owl_loader.hpp"
#include "osm/constants.hpp"
#include "osm/util/quad_tile.hpp"

using namespace pqxx;
using namespace std;
using boost::lexical_cast;
using boost::array;

namespace {
template <typename T>
inline void
flush_buffer(const vector<T> &v, work &w, const char * const table_name) {
  tablewriter writer(w, table_name);
  for (typename vector<T>::const_iterator itr = v.begin(); itr != v.end(); ++itr) {
    const T &t = *itr;
    writer.push_back(t.begin(), t.end());
  }
  writer.complete();
  cout << "flushed table " << table_name << " size " << v.size() << "/" << v.capacity() << endl;
}

template <typename T>
inline T &
push_buffer(vector<T> &v, work &w, const char * const table_name) {
  if (v.size() == v.capacity()) {
    flush_buffer(v, w, table_name);
    v.clear();
  }
  v.push_back(T());
  return v.back();
}

const string &
required_attribute(const tags_t &t, const string &s) {
  tags_t::const_iterator itr = t.find(s);
  if (itr == t.end()) {
    ostringstream ostr;
    ostr << "Missing required attribute `" << s << "'.";
    throw runtime_error(ostr.str());
  }
  return itr->second;
}
} // anonymous namespace

namespace osm { namespace db {

OWLLoader::OWLLoader(connection &c, size_t buffer_size) 
  : transaction(c, "planet_import") {
  // pre-allocate some of the storage in an attempt to be nice & efficient
  nodes_buffer.reserve(buffer_size);
  ways_buffer.reserve(buffer_size);
  relations_buffer.reserve(buffer_size);
  way_nodes_buffer.reserve(buffer_size);
  node_tags_buffer.reserve(buffer_size);
  way_tags_buffer.reserve(buffer_size);
  relation_tags_buffer.reserve(buffer_size);
  relation_members_buffer.reserve(buffer_size);

  // create/truncate tables here
  transaction.exec("drop table if exists nodes, ways, relations, node_tags, way_tags, relation_tags, way_nodes, relation_members, changes");
  transaction.exec("drop type if exists nwr_enum, change_enum");
  transaction.exec("create table nodes (id integer not null, version integer not null, changeset integer not null, "
                   "lat integer not null, lon integer not null, tile bigint not null)");
  transaction.exec("create table ways (id integer not null, version integer not null, changeset integer not null)");
  transaction.exec("create table relations (id integer not null, version integer not null, changeset integer not null)");
  transaction.exec("create table node_tags (id integer not null, k text not null, v text not null)");
  transaction.exec("create table way_tags (id integer not null, k text not null, v text not null)");
  transaction.exec("create table relation_tags (id integer not null, k text not null, v text not null)");
  transaction.exec("create table way_nodes (id integer not null, node_id integer not null, seq integer not null)");
  transaction.exec("create type nwr_enum as enum ('node','way','relation')");
  transaction.exec("create table relation_members (id integer not null, m_role text, m_type nwr_enum not null, m_id integer not null, seq integer not null)");
  transaction.exec("create type change_enum as enum ('create','delete','tags','geometry')");
  transaction.exec("create table changes (elem_type nwr_enum not null, id integer not null, version integer not null, changeset integer not null, change_type change_enum not null, tile bigint not null, time timestamp not null)");
}

OWLLoader::~OWLLoader() throw () {
}

void 
OWLLoader::finish() {
  // flush the buffers into the table writer
  if (nodes_buffer.size() > 0) flush_buffer(nodes_buffer, transaction, "nodes");
  if (ways_buffer.size() > 0) flush_buffer(ways_buffer, transaction, "ways");
  if (relations_buffer.size() > 0) flush_buffer(relations_buffer, transaction, "relations");
  if (node_tags_buffer.size() > 0) flush_buffer(node_tags_buffer, transaction, "node_tags");
  if (way_tags_buffer.size() > 0) flush_buffer(way_tags_buffer, transaction, "way_tags");
  if (relation_tags_buffer.size() > 0) flush_buffer(relation_tags_buffer, transaction, "relation_tags");
  if (way_nodes_buffer.size() > 0) flush_buffer(way_nodes_buffer, transaction, "way_nodes");
  if (relation_members_buffer.size() > 0) flush_buffer(relation_members_buffer, transaction, "relation_members");

  // add some indexes
  // transaction.exec("alter table nodes add primary key (id)");
  // transaction.exec("alter table ways add primary key (id)");
  // transaction.exec("alter table relations add primary key (id)");
  // transaction.exec("create index node_tags_idx on node_tags (id)");
  // transaction.exec("create index way_tags_idx on way_tags (id)");
  // transaction.exec("create index relation_tags_idx on relation_tags (id)");
  // transaction.exec("create index way_nodes_way_idx on way_nodes (id)");
  // transaction.exec("create index way_nodes_node_idx on way_nodes (node_id)");
  // transaction.exec("create index relation_members_relation_idx on relation_members (id)");
  // transaction.exec("create index relation_members_member_idx on relation_members (m_id)");

  // add the bytea tile cache columns to ways and relations
  transaction.exec("alter table ways add column tiles bytea null default null");
  transaction.exec("alter table relations add column tiles bytea null default null");

  // now try and commit the transaction
  transaction.commit();
}

void 
OWLLoader::node(const tags_t &attrs, const tags_t &tags) {
  const string &id = required_attribute(attrs, "id");
  const int lat = lexical_cast<double>(required_attribute(attrs, "lat")) * SCALE;
  const int lon = lexical_cast<double>(required_attribute(attrs, "lon")) * SCALE;
  push_node(lexical_cast<int>(id),
            lexical_cast<int>(required_attribute(attrs, "version")), 
            lexical_cast<int>(required_attribute(attrs, "changeset")),
            lat, lon);
  for (tags_t::const_iterator itr = tags.begin(); itr != tags.end(); ++itr) {
    push_node_tag(id, itr->first, itr->second);
  }
}

void 
OWLLoader::way(const tags_t &attrs, const std::vector<id_t> &way_nodes, const tags_t &tags) {
  const string &ids = required_attribute(attrs, "id");
  const id_t idi = lexical_cast<id_t>(ids);
  push_way(idi, lexical_cast<id_t>(required_attribute(attrs, "version")), lexical_cast<id_t>(required_attribute(attrs, "changeset")));
  for (tags_t::const_iterator itr = tags.begin(); itr != tags.end(); ++itr) {
    push_way_tag(ids, itr->first, itr->second);
  }
  id_t seq = 0;
  for (vector<id_t>::const_iterator itr = way_nodes.begin(); itr != way_nodes.end(); ++itr, ++seq) {
    push_way_node(idi, *itr, seq);
  }
}

void 
OWLLoader::relation(const tags_t &attrs, const std::list<member> &members, const tags_t &tags) {
  const string &ids = required_attribute(attrs, "id");
  const id_t idi = lexical_cast<id_t>(ids);
  push_relation(idi, lexical_cast<id_t>(required_attribute(attrs, "version")), lexical_cast<id_t>(required_attribute(attrs, "changeset")));
  for (tags_t::const_iterator itr = tags.begin(); itr != tags.end(); ++itr) {
    push_relation_tag(ids, itr->first, itr->second);
  }
  size_t seq = 0;
  for (list<member>::const_iterator itr = members.begin(); itr != members.end(); ++itr) {
    push_relation_member(ids, itr->role, itr->type, lexical_cast<string>(itr->id), lexical_cast<string>(seq));
    ++seq;
  }
}

void 
OWLLoader::push_node(int id, int version, int changeset, int lat, int lon) {
  array<int64_t, 6> &node = push_buffer(nodes_buffer, transaction, "nodes");
  node[0] = id;
  node[1] = version;
  node[2] = changeset;
  node[3] = lat;
  node[4] = lon;
  node[5] = util::xy2tile(util::lon2x(lon), util::lat2y(lat));
}

void 
OWLLoader::push_way(id_t id, id_t version, id_t changeset) {
  array<id_t, 3> &way = push_buffer(ways_buffer, transaction, "ways");
  way[0] = id;
  way[1] = version;
  way[2] = changeset;
}

void 
OWLLoader::push_relation(id_t id, id_t version, id_t changeset) {
  array<id_t, 3> &relation = push_buffer(relations_buffer, transaction, "relations");
  relation[0] = id;
  relation[1] = version;
  relation[2] = changeset;
}

void 
OWLLoader::push_node_tag(const std::string &id, const std::string &k, const std::string &v) {
  array<string, 3> &tag = push_buffer(node_tags_buffer, transaction, "node_tags");
  tag[0] = id;
  tag[1] = k;
  tag[2] = v;
}

void 
OWLLoader::push_way_tag(const std::string &id, const std::string &k, const std::string &v) {
  array<string, 3> &tag = push_buffer(way_tags_buffer, transaction, "way_tags");
  tag[0] = id;
  tag[1] = k;
  tag[2] = v;
}

void 
OWLLoader::push_relation_tag(const std::string &id, const std::string &k, const std::string &v) {
  array<string, 3> &tag = push_buffer(relation_tags_buffer, transaction, "relation_tags");
  tag[0] = id;
  tag[1] = k;
  tag[2] = v;
}

void 
OWLLoader::push_way_node(id_t id, id_t node_id, id_t seq) {
  array<id_t, 3> &way_nd = push_buffer(way_nodes_buffer, transaction, "way_nodes");
  way_nd[0] = id;
  way_nd[1] = node_id;
  way_nd[2] = seq;
}

void
OWLLoader::push_relation_member(const std::string &id, const std::string &m_role, const std::string &m_type, 
                                const std::string &m_id, const std::string &seq) {
  array<string, 5> &member = push_buffer(relation_members_buffer, transaction, "relation_members");
  member[0] = id;
  member[1] = m_role;
  member[2] = m_type;
  member[3] = m_id;
  member[4] = seq;
}

} }
