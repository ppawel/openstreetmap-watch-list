#include "osm/data/relation.hpp"

namespace osm {
  namespace data {
    Relation::Relation() 
      : Element(), members() {
    }

    Relation::Relation(const Relation &r) 
      : Element(r), members(r.members) {
    }

    Relation::Relation(id_t id_, version_t version_, timestamp_t time_, const std::vector<member> &members_, const tags_t & tags_) 
      : Element(id_, version_, time_, tags_), members(members_) {
    }
  }
}
