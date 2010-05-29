#include "osm/db/owl_diff/element.hpp"
#include "osm/db/owl_diff/attributes.hpp"
#include <boost/lexical_cast.hpp>

using boost::lexical_cast;

namespace osm { namespace db { namespace owl_diff {

element::element(const tags_t &a, const tags_t &t) 
  : attrs(a), tags(t), 
    id(lexical_cast<id_t>(required_attribute(attrs, "id"))),
    changeset(lexical_cast<id_t>(required_attribute(attrs, "changeset"))),
    version(lexical_cast<id_t>(required_attribute(attrs, "version"))),
    uid(optional_id_attribute(attrs, "uid", 0)),
    visible(optional_bool_attribute(attrs, "visible", true)) {
}

} } }
