#ifndef OSM_IO_EXTENDED_DATABASE_HPP
#define OSM_IO_EXTENDED_DATABASE_HPP

#include <osm/types.hpp>
#include <vector>
#include "osm/io/database.hpp"

namespace osm { namespace io {

/**
 * extended database which allows looking up which way IDs are using
 * a particular node.
 */
class ExtendedDatabase
  : public Database {
public:

  // return way ids which contain the given node id
  virtual std::vector<id_t> ways_using_node(id_t id) = 0;

};

} }

#endif /* OSM_IO_EXTENDED_DATABASE_HPP */
