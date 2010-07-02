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
public:
  typedef std::set<tile_t> tileset_t;

private:
  tileset_t tileset;

public:
  tiler();
  virtual ~tiler() throw();
  
  virtual void add_point(const node &n);
  virtual void add_line_between(const node &a, const node &b);
  virtual void add_tileset(const tileset_t &t);

  // gets an empty tiler of the same type as this, so that tiles can be calculated
  // "offline" and merged back in. used in the tile caching code.
  virtual tiler *empty_tiler() const;

  const tileset_t &tiles() const;
};

} } }

#endif /* OSM_DB_OWL_DIFF_TILER_HPP */
