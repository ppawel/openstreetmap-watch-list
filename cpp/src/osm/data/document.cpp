#include "osm/data/document.hpp"

namespace osm {
  namespace data {
    Document::Document() 
      : nodes(), ways(), relations() {
    }
    
    Document::Document(const Document &d) 
      : nodes(d.nodes), ways(d.ways), relations(d.relations) {
    }

    void 
    Document::set_generator(const std::string &s) {
      generator_ = s;
    }

    const std::string &
    Document::generator() const {
      return generator_;
    }
  }
}
