#include "osm/db/owl_diff/element.hpp"
#include "osm/db/owl_diff/attributes.hpp"
#include <boost/lexical_cast.hpp>

using boost::lexical_cast;

namespace {
  time_t parse_optional_timestamp(const tags_t &t, const std::string &key) {
    tags_t::const_iterator itr = t.find(key);
    if (itr != t.end()) {
      assert(itr->second.size() == 20);
      const char *ptr = itr->second.c_str();

      // 2007-09-21T19:38:53Z
      // ..xx.xx.xx.xx.xx.xx.
      // 00000000001111111111
      // 01234567890123456789
      struct tm t = { 0 };
      
      assert(ptr[0]  == '2');
      assert(ptr[1]  == '0');
      assert(ptr[4]  == '-');
      assert(ptr[7]  == '-');
      assert(ptr[10] == 'T');
      assert(ptr[13] == ':');
      assert(ptr[16] == ':');
      assert(ptr[19] == 'Z');
      
#define twodigit(x) ((x[0] - '0') * 10 + (x[1] - '0'))
      ptr += 2;
      t.tm_year = 100 + twodigit(ptr);
      ptr += 3;
      t.tm_mon = twodigit(ptr) - 1;
      ptr += 3;
      t.tm_mday = twodigit(ptr);
      ptr += 3;
      t.tm_hour = twodigit(ptr);
      ptr += 3;
      t.tm_min = twodigit(ptr);
      ptr += 3;
      t.tm_sec = twodigit(ptr);
#undef twodigit
      
      return timegm(&t);

    } else {
      return time_t(0);
    }
  }
}

namespace osm { namespace db { namespace owl_diff {

element::element(const tags_t &a, const tags_t &t) 
  : attrs(a), tags(t), 
    id(lexical_cast<id_t>(required_attribute(attrs, "id"))),
    changeset(lexical_cast<id_t>(required_attribute(attrs, "changeset"))),
    version(lexical_cast<id_t>(required_attribute(attrs, "version"))),
    uid(optional_id_attribute(attrs, "uid", 0)),
    visible(optional_bool_attribute(attrs, "visible", true)),
    timestamp(parse_optional_timestamp(attrs, "timestamp")) {
}

} } }
