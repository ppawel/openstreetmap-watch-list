#include "osm/io/xml_document_reader.hpp"
#include <libxml++/parsers/textreader.h>
#include <stdexcept>
#include <iostream>
#include <map>
#include <sstream>
#include <boost/lexical_cast.hpp>
#include <tr1/unordered_map>
#include <limits>
#include <vector>
#include <list>

using std::string;
using std::map;
using std::runtime_error;
using xmlpp::TextReader;
using std::cerr;
using std::endl;
using std::ostringstream;
using boost::lexical_cast;
using std::numeric_limits;
using std::vector;
using std::list;

namespace {
typedef std::tr1::unordered_map<string, string> tag_map_t;

void read_xml_tag(tag_map_t &t, TextReader &reader) {
  assert(reader.is_empty_element());
  string k, v;

  while (reader.move_to_next_attribute()) {
    const Glib::ustring &key = reader.get_name();
    const Glib::ustring &val = reader.get_value();
    if (key == "k") {
      k = val;
    } else if (key == "v") {
      v = val;
    }
  }
    
  if (!k.empty() && !v.empty()) {
    t[k] = v;
  }
}

id_t read_xml_nd(TextReader &reader) {
  assert(reader.is_empty_element());
  id_t ref = numeric_limits<id_t>::max();
  
  while (reader.move_to_next_attribute()) {
    const Glib::ustring &key = reader.get_name();
    const Glib::ustring &val = reader.get_value();
    if (key == "ref") {
      ref = lexical_cast<id_t>(val.raw());
    }
  }

  if (ref == numeric_limits<id_t>::max()) {
    ostringstream ostr;
    ostr << "nd element of way doesn't have a ref attribute.";
    throw runtime_error(ostr.str());
  }

  return ref;
}

void read_xml_member(list<osm::member> &members, TextReader &reader) {
  assert(reader.is_empty_element());
  id_t ref = numeric_limits<id_t>::max();
  string type, role;

  while (reader.move_to_next_attribute()) {
    const Glib::ustring &key = reader.get_name();
    const Glib::ustring &val = reader.get_value();
    if (key == "ref") {
      ref = lexical_cast<id_t>(val.raw());
    } else if (key == "type") {
      type = val;
    } else if (key == "role") {
      role = val;
    }
  }

  if (ref == numeric_limits<id_t>::max()) {
    ostringstream ostr;
    ostr << "member element of relation doesn't have a ref attribute.";
    throw runtime_error(ostr.str());
  }
  if (type.empty()) {
    ostringstream ostr;
    ostr << "member element of relation doesn't have a type attribute.";
    throw runtime_error(ostr.str());
  }

  members.push_back(osm::member(ref, role, type));
}

template <class T>
void read_xml(osm::io::Document &doc, TextReader &reader) {
  T::check(reader);

  tag_map_t attrs;
  if (reader.has_attributes()) {
    while (reader.move_to_next_attribute()) {
      const Glib::ustring &key = reader.get_name();
      const Glib::ustring &val = reader.get_value();
      attrs[key] = val;
    }
    reader.move_to_element();
  }
  T t(attrs);

  if (!reader.is_empty_element()) {
    while (reader.read()) {
      if (reader.get_node_type() == TextReader::Element) {
        if (!t.read_child(reader)) {
          ostringstream ostr;
          ostr << "Unexpected element `" << reader.get_name() << "'...";
          throw runtime_error(ostr.str());
        }
      } else if (reader.get_node_type() == TextReader::EndElement) {
        break;
      }
    }
  }
    
  t.add_to_doc(doc);
}

const string &required_attribute(const tag_map_t &t, const string &s) {
  tag_map_t::const_iterator itr = t.find(s);
  if (itr == t.end()) {
    ostringstream ostr;
    ostr << "Missing required attribute `" << s << "'.";
    throw runtime_error(ostr.str());
  }
  return itr->second;
}

struct Node {
   tag_map_t attrs, tags;

   static void check(TextReader &reader) {
     assert(reader.get_name() == "node");
   }

   Node(const tag_map_t &a) 
     : attrs(a) {
   }

   bool read_child(TextReader &reader) {
     const Glib::ustring &name = reader.get_name();
     if (name == "tag") {
       read_xml_tag(tags, reader);
       return true;
     } 
     return false;
   }

   void add_to_doc(osm::io::Document &doc) const {
     doc.node(attrs, tags);
   }
};

struct Way {
   tag_map_t attrs, tags;
   vector<id_t> nds;

   static void check(TextReader &reader) {
     assert(reader.get_name() == "way");
   }

   Way(const tag_map_t &a) 
     : attrs(a) {
   }

   bool read_child(TextReader &reader) {
     const Glib::ustring &name = reader.get_name();
     if (name == "tag") {
       read_xml_tag(tags, reader);
       return true;
     } else if (name == "nd") {
       nds.push_back(read_xml_nd(reader));
       return true;
     }
     return false;
   }

   void add_to_doc(osm::io::Document &doc) const {
     doc.way(attrs, nds, tags);
   }
};

struct Relation {
   tag_map_t attrs, tags;
   list<osm::member> members;

   static void check(TextReader &reader) {
     assert(reader.get_name() == "relation");
   }

   Relation(const tag_map_t &a) 
     : attrs(a) {
   }

   bool read_child(TextReader &reader) {
     const Glib::ustring &name = reader.get_name();
     if (name == "tag") {
       read_xml_tag(tags, reader);
       return true;
     } else if (name == "member") {
       read_xml_member(members, reader);
       return true;
     }
     return false;
   }

   void add_to_doc(osm::io::Document &doc) const {
     doc.relation(attrs, members, tags);
   }
};

struct Bounds {
   static void check(TextReader &reader) {
     assert(reader.get_name() == "bounds");
   }

   Bounds(const tag_map_t &attrs) {
     std::cout << "parsing BOUNDS\n";
   }

   bool read_child(TextReader &reader) {
     return false;
   }

   void add_to_doc(osm::io::Document &doc) {
   }
};

struct Changeset {
   tag_map_t attrs, tags;

   static void check(TextReader &reader) {
     assert(reader.get_name() == "changeset");
   }

   Changeset(const tag_map_t &a) 
     : attrs(a) {
   }

   bool read_child(TextReader &reader) {
     const Glib::ustring &name = reader.get_name();
     if (name == "tag") {
       read_xml_tag(tags, reader);
       return true;
     } 
     return false;
   }

   void add_to_doc(osm::io::Document &doc) const {
     // nothing to do.
   }
};
}

namespace osm { namespace io {

void
read_xml_document(io::Document &doc, const string &file_name) {
  TextReader reader(file_name);
  string version;

  if (!reader.read()) {
    throw runtime_error("Failed to read first element.");
  }

  if ((reader.get_node_type() != TextReader::Element) ||
      (reader.get_name() != "osm")) {
    throw runtime_error("Didn't see a <osm> element in that file anywhere...");
  }

  if (reader.has_attributes()) {
    while (reader.move_to_next_attribute()) {
      const Glib::ustring &value = reader.get_name();
      if (value == "version")
         version = reader.get_value();
    }
  }

  if (version != "0.6") {
    throw runtime_error("Was expecting version 0.6.");
  }

  while (reader.read()) {
    if (reader.get_node_type() == TextReader::Element) {
      const Glib::ustring &name = reader.get_name();
      if (name == "node") {
        read_xml<Node>(doc, reader);
      } else if (name == "way") {
        read_xml<Way>(doc, reader);
      } else if (name == "relation") {
        read_xml<Relation>(doc, reader);
      } else if (name == "changeset") {
        read_xml<Changeset>(doc, reader);
        //throw runtime_error("reading changesets unimplemented");
      } else if (name == "bounds" || name == "bound") {
        //read_xml<Bounds>(doc, reader);
        assert(reader.is_empty_element());
      } else {
        ostringstream ostr;
        ostr << "Unexpected element `" << name << "'.";
        throw runtime_error(ostr.str());
      }
    } else if (reader.get_node_type() == TextReader::EndElement) {
      break;
    }
  }
}

void
read_xml_diff(io::Diff &diff, const string &file_name) {
  TextReader reader(file_name);
  string version;

  if (!reader.read()) {
    throw runtime_error("Failed to read first element.");
  }

  if ((reader.get_node_type() != TextReader::Element) ||
      (reader.get_name() != "osmChange")) {
    throw runtime_error("Didn't see a <osmChange> element in that file anywhere...");
  }

  if (reader.has_attributes()) {
    while (reader.move_to_next_attribute()) {
      const Glib::ustring &value = reader.get_name();
      if (value == "version")
         version = reader.get_value();
    }
  }

  if (version != "0.6") {
    throw runtime_error("Was expecting version 0.6.");
  }

  while (reader.read()) {
    if (reader.get_node_type() == TextReader::Element) {
      const Glib::ustring &name = reader.get_name();
      if (name == "create") {
        diff.set_current_action(io::Diff::Create);
      } else if (name == "modify") {
        diff.set_current_action(io::Diff::Modify);
      } else if (name == "delete") {
        diff.set_current_action(io::Diff::Delete);
      } else {
        ostringstream ostr;
        ostr << "Unexpected action `" << name << "'.";
        throw runtime_error(ostr.str());
      }
      assert(!reader.is_empty_element());

      while (reader.read()) {
        if (reader.get_node_type() == TextReader::Element) {
          const Glib::ustring &name = reader.get_name();
          if (name == "node") {
            read_xml<Node>(diff, reader);
          } else if (name == "way") {
            read_xml<Way>(diff, reader);
          } else if (name == "relation") {
            read_xml<Relation>(diff, reader);
          } else if (name == "changeset") {
            throw runtime_error("reading changesets in diffs unimplemented");
          } else if (name == "bounds" || name == "bound") {
            //read_xml<Bounds>(diff, reader);
            assert(reader.is_empty_element());
          } else {
            ostringstream ostr;
            ostr << "Unexpected element `" << name << "'.";
            throw runtime_error(ostr.str());
          }
        } else if (reader.get_node_type() == TextReader::EndElement) {
          //std::cout << "End of element: " << reader.get_name() << "\n";
          break;
        }
      }
    } else if (reader.get_node_type() == TextReader::EndElement) {
      break;
    }
  }
}

} }
