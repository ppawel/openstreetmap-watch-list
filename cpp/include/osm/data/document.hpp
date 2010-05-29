#ifndef OSM_DATA_DOCUMENT_HPP
#define OSM_DATA_DOCUMENT_HPP

#include "osm/types.hpp"
#include "osm/data/node.hpp"
#include "osm/data/way.hpp"
#include "osm/data/relation.hpp"
#include <vector>

namespace osm {
  namespace data {
    /**
     */
    class Document {
    private:
      std::vector<Node> nodes;
      std::vector<Way> ways;
      std::vector<Relation> relations;

      std::string generator_;
    public:
      Document();
      Document(const Document &);

      void set_generator(const std::string &s);
      const std::string &generator() const;
    };
  }
}

#endif /* OSM_DATA_DOCUMENT_HPP */
