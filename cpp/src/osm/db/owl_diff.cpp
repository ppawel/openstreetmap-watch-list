#include <boost/lexical_cast.hpp>
#include <sstream>
#include <stdexcept>
#include <set>
#include <iostream>

#include "osm/db/owl_diff.hpp"
#include "osm/constants.hpp"
#include "osm/util/quad_tile.hpp"
#include "osm/db/owl_diff/node.hpp"
#include "osm/db/owl_diff/way.hpp"
#include "osm/db/owl_diff/relation.hpp"
#include "osm/db/owl_diff/change.hpp"

using pqxx::work;
using pqxx::connection;
using pqxx::result;
using boost::lexical_cast;
using std::string;
using std::set;
using std::map;
using std::vector;
using std::list;
using std::ostringstream;
using std::runtime_error;
using osm::member;
using std::cout;
using std::endl;
using osm::db::owl_diff::change;
using osm::db::owl_diff::change_list;

namespace osm { namespace db {

bool operator==(const tags_t &a, const tags_t &b) {
  if (a.size() != b.size()) {
    return false;
  }

  for (tags_t::const_iterator atr = a.begin(); atr != a.end(); ++atr) {
    tags_t::const_iterator btr = b.find(atr->first);
    if (btr == b.end()) {
      return false;
    } else if (atr->second != btr->second) {
      return false;
    }
  }

  return true;
}

bool operator!=(const tags_t &a, const tags_t &b) {
  return !(a == b);
}

bool operator==(const list<member> &a, const list<member> &b) {
  if (a.size() != b.size()) {
    return false;
  }
    
  list<member>::const_iterator atr = a.begin();
  list<member>::const_iterator btr = b.begin();
  
  while ((atr != a.end()) && (btr != b.end())) {
    if (*atr != *btr) {
      return false;
    }
  }

  return true;
}

void list_change(const owl_diff::change &ch) {
  switch (ch.action) {
  case change::ChangeCreate:
    cout << "CREATE: ";
    break;
    
  case change::ChangeDelete:
    cout << "DELETE: ";
    break;
    
  case change::ChangeTags:
    cout << "TAGS: ";
    break;
    
  case change::ChangeGeometry:
    cout << "GEOMETRY: ";
    break;
  }

  switch (ch.type) {
  case change::Node:
    cout << "node ";
    break;

  case change::Way:
    cout << "way ";
    break;

  case change::Relation:
    cout << "relation ";
    break;
  }
  
  cout << ch.id << " (v" << ch.version << ") in " << ch.changeset << " covers [";
  for (set<tile_t>::const_iterator jtr = ch.tiles.begin(); jtr != ch.tiles.end(); ++jtr) {
    cout << *jtr << ", ";
  }
  cout << "]" << endl;
}

void list_all_changes(const change_list &c) {
  for (list<owl_diff::change>::const_iterator itr = c.begin(); itr != c.end(); ++itr) {
    list_change(*itr);
  }
}

void mk_change(change_list &l, change::Action a, const owl_diff::node &n, const set<tile_t> &t) {
  change c(a, change::Node, n.id, n.version, n.changeset, n.uid, t);
  l.push_back(c);
}

void mk_change(change_list &l, change::Action a, const owl_diff::way &w, const set<tile_t> &t) {
  change c(a, change::Way, w.id, w.version, w.changeset, w.uid, t);
  l.push_back(c);
}

void mk_change(change_list &l, change::Action a, const owl_diff::relation &r, const set<tile_t> &t) {
  change c(a, change::Relation, r.id, r.version, r.changeset, r.uid, t);
  l.push_back(c);
}

template<class T>
change_list
create(const T &e, osm::db::OWLDatabase &d) {
  change_list changes;
  owl_diff::tiler t;
  e.tiles(t, d);
  mk_change(changes, change::ChangeCreate, e, t.tiles());
  return changes;
}

template<class T>
change_list
do_delete(const T &old_e, const T &e, osm::db::OWLDatabase &d) {
  change_list changes;
  owl_diff::tiler t;
  // NOTE: use the old version of the element to generate the tiles, since the new element may be just
  // empty - many editors remove all nodes/members from deleted items.
  old_e.tiles(t, d);
  mk_change(changes, change::ChangeDelete, e, t.tiles());
  return changes;
}  

template<class T>
change_list
update(const T &old_e, const T &new_e, osm::db::OWLDatabase &d) {
  change_list changes;

  if (!new_e.visible) {
    owl_diff::tiler t;
    old_e.tiles(t, d);
    mk_change(changes, change::ChangeDelete, new_e, t.tiles());

  } else {
    // check if tags are updated
    if (old_e.tags != new_e.tags) {
      owl_diff::tiler t;
      old_e.tiles(t, d);
      new_e.tiles(t, d);
      mk_change(changes, change::ChangeTags, new_e, t.tiles());
    }

    // check if geometry was updated
    if (old_e.geom_is_different(new_e)) {
      owl_diff::tiler t;
      old_e.diff_tiles(new_e, t, d);
      mk_change(changes, change::ChangeGeometry, new_e, t.tiles());
    }
  }

  return changes;
}

template<class T>
change_list
common(T &new_e, osm::db::OWLDatabase &d, io::Diff::Action action) {
  id_t id = new_e.id;
  change_list changes;

  // force deleted status on delete actions
  if (action == io::Diff::Delete) {
    new_e.visible = false;
  }

  if (T::db_exists(id, d)) {
    T old_e = T::db_load(id, d);

    // existing element - check the version
    version_t old_ver = old_e.version;
    version_t new_ver = new_e.version;

    /* not yet - we'll get around to this later...
    while (new_ver > old_ver + 1) {
      // get intervening versions from the API, updating old_ver.
      T mid_e;
      
      APIDatabase api_db;
      if (!mid_e.db_load(api_db, id, old_ver + 1)) {
	throw not_found("api database", id, old_ver + 1);
      }

      changes.splice(changes.end(), update(old_e, mid_e));
      old_e = mid_e;
    } 
    */
    if (new_ver <= old_ver) {
      if (new_ver == old_ver) {
	cout << "WARNING: Not applying change to " << T::type << " " << id 
	     << ", at same version " << new_ver << "." << endl;
      } else {
	cout << "WARNING: Not applying downgrade to " << T::type << " " << id 
	     << ", versions " << old_ver << " -> " << new_ver << "." << endl;
      }
    } else {
      if (new_ver > old_ver + 1) {
	cout << "WARNING: Skipping versions in " << T::type << " " << id 
	     << ", versions " << old_ver << " -> " << new_ver << "." << endl;
      }

      // add changes to database.
      if (action == io::Diff::Delete) {
	splice_changes(changes, do_delete(old_e, new_e, d));
      } else {
	splice_changes(changes, update(old_e, new_e, d));
      }
      T::db_save(new_e, d);
    }

  } else {
    if (action == io::Diff::Delete) {
      cout << "WARNING: Not re-deleting " << T::type << " " << id 
	   << ", is already deleted." << endl;
    } else {
      // must be a new or undeleted element
      splice_changes(changes, create(new_e, d));
      T::db_save(new_e, d);
    }
  }

  return changes;
}

OWLDiff::OWLDiff(OWLDatabase &db, Mode m) 
  : database(db), mode(m) {
}

OWLDiff::~OWLDiff() throw() {
}

void 
OWLDiff::finish() {
  if (mode == DebugMode) {
    list_all_changes(all_changes);

    for (map<id_t, string>::iterator itr = users_seen.begin(); itr != users_seen.end(); ++itr) {
      cout << "USER(" << itr->first << ") = `" << itr->second << "'" << endl;
    }
  } else {
    const change_list &c = all_changes;
    for (list<owl_diff::change>::const_iterator itr = c.begin(); itr != c.end(); ++itr) {
      database.insert_change(*itr);
    }

    database.update_users(users_seen);
    database.update_changesets(changesets_seen);
  }
}

void 
OWLDiff::node(const tags_t &attrs, const tags_t &tags) {
  owl_diff::node n(attrs, tags);
  update_metadata(attrs);
  list<owl_diff::change> changes = common(n, database, current_action);
  all_changes.splice(all_changes.end(), changes);
}

void 
OWLDiff::way(const tags_t &attrs, const std::vector<id_t> &way_nodes, const tags_t &tags) {
  owl_diff::way w(attrs, tags, way_nodes);
  update_metadata(attrs);
  list<owl_diff::change> changes = common(w, database, current_action);
  all_changes.splice(all_changes.end(), changes);
}

void 
OWLDiff::relation(const tags_t &attrs, const std::list<member> &members, const tags_t &tags) {
  owl_diff::relation r(attrs, tags, members);
  update_metadata(attrs);
  list<owl_diff::change> changes = common(r, database, current_action);
  all_changes.splice(all_changes.end(), changes);
}

void 
OWLDiff::set_current_action(io::Diff::Action a) {
  current_action = a;
}

const owl_diff::change_list &
OWLDiff::changes_list() const {
  return all_changes;
}

void 
OWLDiff::update_metadata(const tags_t &attrs) {
  tags_t::const_iterator uid_itr = attrs.find("uid");
  tags_t::const_iterator user_itr = attrs.find("user");
  tags_t::const_iterator changeset_itr = attrs.find("changeset");

  if ((uid_itr != attrs.end()) &&
      (user_itr != attrs.end()) &&
      (changeset_itr != attrs.end())) {
    id_t id = lexical_cast<id_t>(uid_itr->second);
    const string &name = user_itr->second;
    id_t cs_id = lexical_cast<id_t>(changeset_itr->second);

    map<id_t, string>::iterator itr = users_seen.find(id);
    if (itr != users_seen.end()) {
      if (itr->second != name) {
	itr->second = name;
      }
    } else {
      users_seen.insert(std::make_pair(id, name));
    }

    map<id_t, id_t>::iterator jtr = changesets_seen.find(cs_id);
    if (jtr == changesets_seen.end()) {
      changesets_seen.insert(std::make_pair(cs_id, id));
    } else {
      // this should be forbidden by the OSM data model... but it's always worth
      // checking these things.
      if (jtr->second != id) {
	throw runtime_error("Changeset ID refers to two different user IDs!");
      }
    }
  }
}

} }
