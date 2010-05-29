#ifndef OSM_DATA_ELEMENT_HPP
#define OSM_DATA_ELEMENT_HPP

#include "osm/types.hpp"

namespace osm {
  namespace data {
    /**
     */
    class Element {
    private:
      id_t id;
      version_t version;
      timestamp_t timestamp;
      tags_t tags;
    public:
      Element();
      Element(const Element &);
      Element(id_t, version_t, timestamp_t, const tags_t &);
    };
  }
}

#endif /* OSM_DATA_ELEMENT_HPP */
