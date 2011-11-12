#include "osm/db/owl_diff/attributes.hpp"
#include <boost/lexical_cast.hpp>
#include <sstream>
#include <stdexcept>

using std::string;
using std::ostringstream;
using std::runtime_error;
using boost::lexical_cast;

namespace osm { namespace db { namespace owl_diff {

const string &required_attribute(const tags_t &t, const string &s) {
  tags_t::const_iterator itr = t.find(s);
  if (itr == t.end()) {
    ostringstream ostr;
    ostr << "Missing required attribute `" << s << "'. Tags are {";
    for (itr = t.begin(); itr != t.end(); ++itr) {
      ostr << "`" << itr->first << "'=`" << itr->second << "', ";
    }
    ostr << "}.";
    throw runtime_error(ostr.str());
  }
  return itr->second;
}

bool optional_bool_attribute(const tags_t &t, const string &s, bool def) {
  tags_t::const_iterator itr = t.find(s);
  if (itr == t.end()) {
    return def;
  }
  const string v = itr->second;
  if (v[0] == 't' || v[0] == 'T') {
    return true;
  } else {
    return false;
  }
}

id_t optional_id_attribute(const tags_t &t, const std::string &s, id_t def) {
  tags_t::const_iterator itr = t.find(s);
  if (itr == t.end()) {
    return def;
  }
  return lexical_cast<id_t>(itr->second);
}

} } }
