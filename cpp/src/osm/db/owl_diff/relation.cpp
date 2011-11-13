#include "osm/db/owl_diff/relation.hpp"
#include "osm/db/owl_diff/node.hpp"
#include "osm/db/owl_diff/way.hpp"
#include <stdexcept>
#include <sstream>

using std::vector;
using std::list;
using std::set;
using std::runtime_error;
using std::ostringstream;

namespace {
struct set_member {
   enum Type { Node, Way, Relation };
   id_t id;
   Type type;

   set_member(id_t i, Type t) : id(i), type(t) {}
   bool operator<(const set_member &s) const {
     return type < s.type || (type == s.type && id < s.id);
   }
};

set<set_member> make_set(const list<osm::member> &l) {
  set<set_member> s;
  for (list<osm::member>::const_iterator itr = l.begin(); itr != l.end(); ++itr) {
    set_member::Type t;
    if (itr->type == "node") {
      t = set_member::Node;
    } else if (itr->type == "way") {
      t = set_member::Way;
    } else {
      t = set_member::Relation;
    }
    s.insert(set_member(itr->id, t));
  }
  return s;
}
}

namespace osm { namespace db { namespace owl_diff {

const char *relation::type = "relation";

relation::relation(const tags_t &a, const tags_t &t, const std::list<member> &m) 
  : element(a, t), members(m) {
}

bool relation::geom_is_different(const relation &r) const {
  return members != r.members;
}

void relation::tiles(tiler &t, osm::io::Database &d) const {
  // a relation covers all its members. need some slight-of-hand here
  // to handle recursive relations.
  set<id_t> ids;
  recursive_tiles(ids, t, d);
}

void relation::diff_tiles(const relation &w, tiler &t, osm::io::Database &d) const {
  // if tags changed then it's just the tiles covering the old and
  // new versions (which may be the same if only the tags changed).
  // if only members changed then only the tiles covered by changed
  // members are considered (this treats the relation in a set-like
  // manner, not a list-like manner, but i'm not sure it makes more
  // sense to do it in a list-like manner.
  set<set_member> s1 = make_set(members);
  set<set_member> s2 = make_set(w.members);
  set<set_member> difference;
  
  set_difference(s1.begin(), s1.end(), s2.begin(), s2.end(), inserter(difference, difference.begin()));

  set<id_t> relation_ids;
  relation_ids.insert(id);

  for (set<set_member>::iterator itr = difference.begin(); itr != difference.end(); ++itr) {
    if (itr->type == set_member::Node) {
      if (node::db_exists(itr->id, d)) {
        node n = node::db_load(itr->id, d);
        t.add_point(n);
      }
    } else if (itr->type == set_member::Way) {
      if (way::db_exists(itr->id, d)) {
        way w = way::db_load(itr->id, d);
        w.tiles(t, d);
      }
    } else {
      if ((relation_ids.count(itr->id) == 0) && relation::db_exists(itr->id, d)) {
        relation r = relation::db_load(itr->id, d);
        r.recursive_tiles(relation_ids, t, d);
      }
    }
  }
}

void relation::recursive_tiles(set<id_t> &ids, tiler &t, osm::io::Database &d) const {
  // insert this relation's ID into the "seen" set.
  ids.insert(id);
  for (list<member>::const_iterator itr = members.begin(); 
       itr != members.end(); ++itr) {
    if (itr->type == "node") {
      if (node::db_exists(itr->id, d)) {
        node n = node::db_load(itr->id, d);
        t.add_point(n);
      }
    } else if (itr->type == "way") {
      if (way::db_exists(itr->id, d)) {
        way w = way::db_load(itr->id, d);
        w.tiles(t, d);
      }
    } else if (itr->type == "relation") {
      // only follow relation member if it isn't already in the list of "seen" IDs
      if ((ids.count(itr->id) == 0) && relation::db_exists(itr->id, d)) {
        relation r = relation::db_load(itr->id, d);
        r.recursive_tiles(ids, t, d);
      }
    } else {
      ostringstream ostr;
      ostr << "Unrecognised member type `" << itr->type << "'";
      throw runtime_error(ostr.str());
    }
  }
}

bool 
relation::db_exists(id_t i, osm::io::Database &d) {
  tags_t attrs, tags;
  list<member> members;
  return d.relation(i, attrs, members, tags);
}

relation 
relation::db_load(id_t i, osm::io::Database &d) {
  tags_t attrs, tags;
  list<member> members;
  bool ok = d.relation(i, attrs, members, tags);
  if (!ok) {
    throw runtime_error("Can't load relation from database!");
  }
  return relation(attrs, tags, members);
}

void 
relation::db_save(const relation &r, osm::db::OWLDatabase &d) {
  if (r.visible) {
    d.update_relation(r.id, r.attrs, r.members, r.tags);
  } else {
    d.delete_relation(r.id);
  }
}

} } }
