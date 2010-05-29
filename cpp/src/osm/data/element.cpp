#include "osm/data/element.hpp"

namespace osm {
  namespace data {
    Element::Element() 
      : id(0), version(0), timestamp(), tags() {
    }

    Element::Element(const Element &e) 
      : id(e.id), version(e.version), timestamp(e.timestamp), tags(e.tags) {
    }

    Element::Element(id_t id_, version_t version_, timestamp_t time_, const tags_t & tags_) 
      : id(id_), version(version_), timestamp(time_), tags(tags_) {
    }
  }
}
