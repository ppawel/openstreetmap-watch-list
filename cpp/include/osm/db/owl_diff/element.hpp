#ifndef OSM_DB_OWL_DIFF_ELEMENT_HPP
#define OSM_DB_OWL_DIFF_ELEMENT_HPP

#include "osm/types.hpp"
#include <time.h>

namespace osm { namespace db { namespace owl_diff {

/**
 * base type of elements in the OWL internal workings.
 */
struct element {
  tags_t attrs;
  tags_t tags;
  id_t id, changeset, version, uid;
  bool visible;
  time_t timestamp;

  element(const tags_t &a, const tags_t &t); 
};

} } }

#endif /* OSM_DB_OWL_DIFF_ELEMENT_HPP */
