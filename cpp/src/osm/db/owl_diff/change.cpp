#include "osm/db/owl_diff/change.hpp"

namespace osm { namespace db { namespace owl_diff {

change::change(Action a, Type t, const id_t i, const id_t v, const id_t cs, const id_t ui, const std::set<tile_t> &ts)
  : action(a), type(t), id(i), version(v), changeset(cs), uid(ui), tiles(ts) {
}

change::change(const change &c)
  : action(c.action), type(c.type), id(c.id), version(c.version), changeset(c.changeset), uid(c.uid), tiles(c.tiles) {
}

} } }
