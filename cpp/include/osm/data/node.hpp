#ifndef OSM_DATA_NODE_HPP
#define OSM_DATA_NODE_HPP

#include "osm/types.hpp"
#include "osm/data/element.hpp"

namespace osm { 
  namespace data {
    /**
     */
    class Node 
      : public Element {
    private:
      double longitude, latitude;
    public:
      Node();
      Node(const Node &);
      Node(id_t, version_t, timestamp_t, double, double, const tags_t &);
    };
  }
}

#endif /* OSM_DATA_NODE_HPP */
