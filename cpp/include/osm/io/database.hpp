#ifndef OSM_IO_DATABASE_HPP
#define OSM_IO_DATABASE_HPP

#include <osm/types.hpp>
#include <osm/member.hpp>
#include <vector>
#include <list>

namespace osm { namespace io {

/**
 * an interface for "databases", or stores of OSM elements which can
 * be queried. in this simple interface the only query is by element
 * type and ID, returning the element attributes.
 */
class Database {
public:

  virtual ~Database() throw();

  /**
   * looks up a node by its ID and returns the attributes and tags in
   * the reference parameters. the inout parameters may or may not be
   * reinitialised. returns true if the node was found, false 
   * otherwise.
   */
  virtual bool node(id_t id, tags_t &attrs, tags_t &tags) = 0;

  /**
   * looks up a way by its ID, returning results in the reference
   * parameters. returns true if the way was found.
   */
  virtual bool way(id_t id, tags_t &attrs, std::vector<id_t> &way_nodes, tags_t &tags) = 0;

  /**
   * looks up a relation by ID, returning the results in the given
   * reference parameters. returns true if the relation was found.
   */
  virtual bool relation(id_t id, tags_t &attrs, std::list<member> &members, tags_t &tags) = 0;
};

} }

#endif /* OSM_IO_DATABASE_HPP */
