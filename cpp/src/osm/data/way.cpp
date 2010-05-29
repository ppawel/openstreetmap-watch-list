#include "osm/data/way.hpp"

namespace osm {
  namespace data {
    Way::Way() 
      : Element(), nodes() {
    }

    Way::Way(const Way &w) 
      : Element(w), nodes(w.nodes) {
    }

    Way::Way(id_t id_, version_t version_, timestamp_t time_, const std::vector<id_t> &nodes_, const tags_t & tags_) 
      : Element(id_, version_, time_, tags_), nodes(nodes_) {
    }
  }
}
