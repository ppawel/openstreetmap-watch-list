#include "osm/io/api_database.hpp"
#include "osm/io/document.hpp"
#include "osm/io/xml_document_reader.hpp"
#include <sstream>

using std::string;
using std::vector;
using std::list;
using std::ostringstream;

namespace {
class Fulcrum
  : public osm::io::Document {
public:
  tags_t attrs, tags;
  vector<id_t> way_nodes;
  list<osm::member> members;
  unsigned int elem_count;

  Fulcrum(const string &root, const char * const model, id_t id)
    : elem_count(0) {
    try {
      ostringstream ostr;
      ostr << root << "/" << model << "/" << id;
      osm::io::read_xml_document(*this, ostr.str());
    } catch (...) {
      // we don't care about errors - we'll figure that out later.
    }
  }

  ~Fulcrum() throw() {}

  void node(const tags_t &a, const tags_t &t) {
    attrs = a;
    tags = t;
    ++elem_count;
  }

  void way(const tags_t &a, const std::vector<id_t> &wn, const tags_t &t) {
    attrs = a;
    way_nodes = wn;
    tags = t;
    ++elem_count;
  }

  void relation(const tags_t &a, const std::list<osm::member> &m, const tags_t &t) {
    attrs = a;
    members = m;
    tags = t;
    ++elem_count;
  }
};
}

namespace osm { namespace io {

APIDatabase::APIDatabase() 
  : api_root("http://www.openstreetmap.org/api/0.6") {
}

APIDatabase::APIDatabase(std::string root) 
  : api_root(root) {
}

APIDatabase::~APIDatabase() throw() {
}

bool 
APIDatabase::node(id_t id, tags_t &attrs, tags_t &tags) {
  Fulcrum fulcrum(api_root, "node", id);
  bool found = fulcrum.elem_count == 1;

  if (found) {
    swap(attrs, fulcrum.attrs);
    swap(tags, fulcrum.tags);
  }

  return found;
}

bool 
APIDatabase::way(id_t id, tags_t &attrs, std::vector<id_t> &way_nodes, tags_t &tags) {
  Fulcrum fulcrum(api_root, "way", id);
  bool found = fulcrum.elem_count == 1;

  if (found) {
    swap(attrs, fulcrum.attrs);
    swap(way_nodes, fulcrum.way_nodes);
    swap(tags, fulcrum.tags);
  }

  return found;
}

bool 
APIDatabase::relation(id_t id, tags_t &attrs, std::list<member> &members, tags_t &tags) {
  Fulcrum fulcrum(api_root, "relation", id);
  bool found = fulcrum.elem_count == 1;

  if (found) {
    swap(attrs, fulcrum.attrs);
    members.swap(fulcrum.members);
    swap(tags, fulcrum.tags);
  }

  return found;
}

} }
