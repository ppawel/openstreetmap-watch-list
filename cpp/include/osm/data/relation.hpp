#ifndef OSM_DATA_RELATION_HPP
#define OSM_DATA_RELATION_HPP

#include "osm/types.hpp"
#include "osm/data/element.hpp"
#include <vector>

namespace osm { 
  namespace data {
    /**
     */
    class Relation 
      : public Element {
    public:
      struct member {
	enum element_t { Node, Way, Relation };
	id_t id;
	element_t type;
	string_t role;
      };
    private:
      std::vector<member> members;
    public:
      Relation();
      Relation(const Relation &);
      Relation(id_t, version_t, timestamp_t, const std::vector<member> &, const tags_t &);
    };
  }
}

#endif /* OSM_DATA_RELATION_HPP */
