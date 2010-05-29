#include "osm/data/node.hpp"

namespace osm {
  namespace data {
    Node::Node() 
      : Element(), longitude(0.0), latitude(0.0) {
    }

    Node::Node(const Node &n) 
      : Element(n), longitude(n.longitude), latitude(n.latitude) {
    }

    Node::Node(id_t id_, version_t version_, timestamp_t time_, double lon_, double lat_, const tags_t & tags_) 
      : Element(id_, version_, time_, tags_), longitude(lon_), latitude(lat_) {
    }
  }
}
