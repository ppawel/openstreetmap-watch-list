#ifndef OSM_DB_OWL_DIFF_CHANGE_HPP
#define OSM_DB_OWL_DIFF_CHANGE_HPP

#include <set>
#include <list>
#include "osm/types.hpp"

namespace osm { namespace db { namespace owl_diff {

/**
 * encapsulates a change, which will be written to the changes table
 * of the OWL database.
 */
struct change {
  enum Action {
    ChangeCreate   = 0,
    ChangeDelete   = 1,
    ChangeTags     = 2,
    ChangeGeometry = 3
  };
  enum Type {
    Node     = 0,
    Way      = 1,
    Relation = 2
  };

  const Action action;
  const Type type;
  const id_t id, version, changeset, uid;
  const std::set<tile_t> tiles;

  change(Action a, Type t, const id_t i, const id_t v, const id_t cs, const id_t ui, const std::set<tile_t> &ts);
  change(const change &);
};

// handy reference for the changes we're actually going to be using
// and passing around most of the time.
typedef std::list<change> change_list;

// note: may need to remove reference from b, as the STL doesn't
// seem to like this.
inline void splice_changes(change_list &a, change_list b) {
  a.splice(a.end(), b);
}

} } }

#endif /* OSM_DB_OWL_DIFF_CHANGE_HPP */
