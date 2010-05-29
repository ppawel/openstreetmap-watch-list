#include "osm/db/owl_database.hpp"
#include "osm/util/quad_tile.hpp"
#include "osm/constants.hpp"

#include <boost/lexical_cast.hpp>
#include <sstream>
#include <iostream>

using pqxx::work;
using pqxx::connection;
using pqxx::result;
using boost::lexical_cast;
using namespace std;

namespace {

/**
 * generic element-finding code. returns false if the ID could not be found.
 */
bool find_element(pqxx::work &w, const char * const table, const char * const tags_table, id_t id, tags_t &attrs, tags_t &tags) {
  stringstream query;
  query << "select * from " << table << " where id=" << id;
  result res = w.exec(query);
  
  bool found_one = res.size() == 1;
  
  if (found_one) {
    const result::tuple &row = res[0];
    for (result::tuple::const_iterator itr = row.begin(); itr != row.end(); ++itr) {
      attrs[itr->name()] = itr->c_str();
    }

    stringstream tags_query;
    tags_query << "select k,v from " << tags_table << " where id=" << id;
    result tag_res = w.exec(tags_query);
    for (result::const_iterator itr = tag_res.begin(); itr != tag_res.end(); ++itr) {
      tags[itr->at(0).c_str()] = itr->at(1).c_str();
    }
  } else if (res.size() > 1) {
    ostringstream ostr;
    ostr << "Found " << res.size() << " " << table << " with ID = " << id << ". Database is broken.";
    throw runtime_error(ostr.str());
  }

  return found_one;
}

void
add_tags(pqxx::work &w, const char * const tags_table, id_t id, const tags_t &tags) {
  if (tags.size() > 0) {
    stringstream query;
    query << "insert into " << tags_table << " (id, k, v) values ";
    for (tags_t::const_iterator itr = tags.begin(); itr != tags.end(); ++itr) {
      if (itr != tags.begin()) query << ", ";
      query << "(" << id << ", E'" << w.esc(itr->first) << "', E'" << w.esc(itr->second) << "')";
    }
    w.exec(query);
  }
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

template <class T>
string
to_string(const T &t) {
  ostringstream ostr;
  ostr << t;
  return ostr.str();
}

string
to_string_d(const double &d) {
  ostringstream ostr;
  ostr.precision(7);
  ostr.setf(std::ios::fixed,std::ios::floatfield);
  ostr << d;
  return ostr.str();
}

} // anonymous namespace

namespace osm { namespace db {

OWLDatabase::OWLDatabase(connection &c) 
  : transaction(c, "owl_db_query") {
}

OWLDatabase::~OWLDatabase() throw() {
}

void 
OWLDatabase::finish() {
  transaction.commit();
}

bool 
OWLDatabase::node(id_t id, tags_t &attrs, tags_t &tags) {
  bool found = find_element(transaction, "nodes", "node_tags", id, attrs, tags);
  if (found) {
    const double lat = lexical_cast<double>(required_attribute(attrs, "lat")) / SCALE;
    const double lon = lexical_cast<double>(required_attribute(attrs, "lon")) / SCALE;
    attrs["lat"] = to_string_d(lat);
    attrs["lon"] = to_string_d(lon);
  }
  return found;
}

bool 
OWLDatabase::way(id_t id, tags_t &attrs, vector<id_t> &way_nodes, tags_t &tags) {
  bool found = find_element(transaction, "ways", "way_tags", id, attrs, tags);
  
  if (found) {
    stringstream query;
    query << "select node_id from way_nodes where id=" << id << " order by seq asc";
    result res = transaction.exec(query);

    way_nodes.clear();
    way_nodes.reserve(res.size());
    for (result::const_iterator itr = res.begin(); itr != res.end(); ++itr) {
      way_nodes.push_back(itr->at(0).as<id_t>());
    }
  }

  return found;
}

bool 
OWLDatabase::relation(id_t id, tags_t &attrs, list<member> &members, tags_t &tags) {
  bool found = find_element(transaction, "relations", "relation_tags", id, attrs, tags);
  const string empty;

  if (found) {
    stringstream query;
    query << "select m_id, m_role, m_type from relation_members where id=" << id << " order by seq asc";
    result res = transaction.exec(query);

    members.clear();
    for (result::const_iterator itr = res.begin(); itr != res.end(); ++itr) {
      members.push_back(member(itr->at(0).as<id_t>(), itr->at(1).as<string>(empty), itr->at(2).as<string>()));
    }
  }

  return found;
}

// return way ids which contain the given node id
vector<id_t> 
OWLDatabase::ways_using_node(id_t id) {
  vector<id_t> node_ways;

  stringstream query;
  query << "select distinct id from way_nodes where node_id=" << id;
  result res = transaction.exec(query);

  node_ways.reserve(res.size());
  for (result::const_iterator itr = res.begin(); itr != res.end(); ++itr) {
    node_ways.push_back(itr->at(0).as<id_t>());
  }

  return node_ways;
}

// setters
void
OWLDatabase::update_node(id_t id, const tags_t &attrs, const tags_t &tags) {
  // simple implementation as a delete-add. this isn't efficient, but it might not need to be.
  const int lat = lexical_cast<double>(required_attribute(attrs, "lat")) * SCALE;
  const int lon = lexical_cast<double>(required_attribute(attrs, "lon")) * SCALE;
  delete_node(id);

  stringstream query;
  query << "insert into nodes (id, version, changeset, lat, lon, tile) values ("
	<< id << ", "
	<< required_attribute(attrs, "version") << ", "
	<< required_attribute(attrs, "changeset") << ", "
	<< lat << ", " << lon << ", "
	<< util::xy2tile(util::lon2x(lon), util::lat2y(lat)) << ")";
  transaction.exec(query);

  add_tags(transaction, "node_tags", id, tags);
}

void 
OWLDatabase::update_way(id_t id, const tags_t &attrs, const vector<id_t> &way_nodes, const tags_t &tags) {
  // simple implementation as a delete-add. this isn't efficient, but it might not need to be.
  delete_way(id);

  {
    stringstream query;
    query << "insert into ways (id, version, changeset) values ("
	  << id << ", "
	  << required_attribute(attrs, "version") << ", "
	  << required_attribute(attrs, "changeset") << ")";
    transaction.exec(query);
  }

  // update way nodes
  if (way_nodes.size() > 0) {
    stringstream query;
    query << "insert into way_nodes (id, node_id, seq) values ";
    for (size_t i = 0; i < way_nodes.size(); ++i) {
      if (i > 0) query << ", ";
      query << "(" << id << ", " << way_nodes[i] << ", " << i << ")";
    }
    transaction.exec(query);
  }

  add_tags(transaction, "way_tags", id, tags);
}

void 
OWLDatabase::update_relation(id_t id, const tags_t &attrs, const list<member> &members, const tags_t &tags) {
  // simple implementation as a delete-add. this isn't efficient, but it might not need to be.
  delete_relation(id);

  stringstream query;
  query << "insert into relations (id, version, changeset) values ("
	<< id << ", "
	<< required_attribute(attrs, "version") << ", "
	<< required_attribute(attrs, "changeset") << ")";
  transaction.exec(query);

  // update relation members
  if (members.size() > 0) {
    stringstream query;
    query << "insert into relation_members (id, m_id, m_role, m_type, seq) values ";
    size_t i = 0;
    for (list<member>::const_iterator itr = members.begin(); itr != members.end(); ++itr) {
      if (i > 0) query << ", ";
      query << "(" << id << ", " << itr->id << ", E'" << transaction.esc(itr->role) << "', '" << itr->type << "', " << i << ")";
      ++i;
    }
    transaction.exec(query);
  }

  add_tags(transaction, "relation_tags", id, tags);
}

// deleters
void 
OWLDatabase::delete_node(id_t id) {
  stringstream query;
  query << "delete from nodes where id=" << id << "; delete from node_tags where id=" << id;
  transaction.exec(query);
}

void 
OWLDatabase::delete_way(id_t id) {
  stringstream query;
  query << "delete from ways where id=" << id << "; delete from way_tags where id=" << id << "; delete from way_nodes where id=" << id;
  transaction.exec(query);
}

void 
OWLDatabase::delete_relation(id_t id) {
  stringstream query;
  query << "delete from relations where id=" << id << "; delete from relation_tags where id=" << id << "; delete from relation_members where id=" << id;
  transaction.exec(query);
}

void
OWLDatabase::insert_change(const owl_diff::change &c) {
  for (set<tile_t>::const_iterator itr = c.tiles.begin(); itr != c.tiles.end(); ++itr) {
    stringstream query;
    query << "insert into changes (elem_type, id, version, changeset, change_type, tile, time) values (";
    if (c.type == owl_diff::change::Node) {
      query << "'node'";
    } else if (c.type == owl_diff::change::Way) {
      query << "'way'";
    } else {
      query << "'relation'";
    }
    query << ", " << c.id << ", " << c.version << ", " << c.changeset << ", ";
    if (c.action == owl_diff::change::ChangeCreate) {
      query << "'create'";
    } else if (c.action == owl_diff::change::ChangeDelete) {
      query << "'delete'";
    } else if (c.action == owl_diff::change::ChangeTags) {
      query << "'tags'";
    } else {
      query << "'geometry'";
    }
    query << ", " << *itr << ", localtimestamp)";
    transaction.exec(query);
  }
}

void
OWLDatabase::update_users(const map<id_t, string> &users) {
  for (map<id_t, string>::const_iterator itr = users.begin(); itr != users.end(); ++itr) {
    stringstream find_query;
    find_query << "select name from users where id = " << itr->first;
    pqxx::result find_res = transaction.exec(find_query);
    if (find_res.size() > 0) {
      if (itr->second != find_res[0][0].c_str()) {
	stringstream update_query;
	update_query << "update users set name='" << transaction.esc(itr->second) << "' where id=" << itr->first;
	transaction.exec(update_query);
      }
    } else {
      stringstream insert_query;
      insert_query << "insert into users (id, name) values (" << itr->first << ", '" << transaction.esc(itr->second) << "')";
      transaction.exec(insert_query);
    }
  }
}

void
OWLDatabase::update_changesets(const map<id_t, id_t> &changesets) {
  for (map<id_t, id_t>::const_iterator itr = changesets.begin(); itr != changesets.end(); ++itr) {
    stringstream find_query;
    find_query << "select uid from changeset_details where id=" << itr->first;
    pqxx::result find_res = transaction.exec(find_query);
    if (find_res.size() > 0) {
      // if the changeset has been updated then reset the closed and last-seen time. these will be
      // picked up by a daemon externally which will refresh the comment.
      stringstream update_query;
      update_query << "update changeset_details set closed=false,last_seen=now() where id=" << itr->first;
      transaction.exec(update_query);

    } else {
      stringstream insert_query;
      insert_query << "insert into changeset_details (id, uid, closed, last_seen) values (" 
		   << itr->first << ", " << itr->second << ", false, now())";
      transaction.exec(insert_query);
    }
  }
}

} }
