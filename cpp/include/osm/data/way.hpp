#ifndef OSM_DATA_WAY_HPP
#define OSM_DATA_WAY_HPP

#include "osm/types.hpp"
#include "osm/data/element.hpp"
#include <vector>

namespace osm { 
  namespace data {
    /**
     */
    class Way 
      : public Element {
    private:
      std::vector<id_t> nodes;
    public:
      Way();
      Way(const Way &);
      Way(id_t, version_t, timestamp_t, const std::vector<id_t> &, const tags_t &);
    };
  }
}

#endif /* OSM_DATA_WAY_HPP */
