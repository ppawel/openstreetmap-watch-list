#ifndef OSM_DB_OWL_DIFF_ATTRIBUTES_HPP
#define OSM_DB_OWL_DIFF_ATTRIBUTES_HPP

#include <string>
#include "osm/types.hpp"

namespace osm { namespace db { namespace owl_diff {

const std::string &required_attribute(const tags_t &t, const std::string &s);
bool optional_bool_attribute(const tags_t &t, const std::string &s, bool def);
id_t optional_id_attribute(const tags_t &t, const std::string &s, id_t def);

} } }

#endif /* OSM_DB_OWL_DIFF_ATTRIBUTES_HPP */
