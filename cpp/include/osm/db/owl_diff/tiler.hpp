#ifndef OSM_DB_OWL_DIFF_TILER_HPP
#define OSM_DB_OWL_DIFF_TILER_HPP

#include <set>
#include "osm/types.hpp"
#include "osm/db/owl_diff/node.hpp"

namespace osm { namespace db { namespace owl_diff {

/**
 * abstract away the innards of keeping track of tiles which have been
 * touched so that the tile expiry code and code for determining the changes
 * on an element can be tested.
 */
class tiler {
private:
  typedef std::set<tile_t> tileset_t;
  tileset_t tileset;

public:
  tiler();
  virtual ~tiler() throw();
  
  virtual void add_point(const node &n);
  virtual void add_line_between(const node &a, const node &b);
  
  const tileset_t &tiles() const;
};

} } }

#endif /* OSM_DB_OWL_DIFF_TILER_HPP */
