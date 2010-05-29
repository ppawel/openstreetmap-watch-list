#ifndef OSM_IO_DOCUMENT_HPP
#define OSM_IO_DOCUMENT_HPP

#include <osm/types.hpp>
#include <osm/member.hpp>
#include <vector>
#include <list>

namespace osm { namespace io {

/**
 * implement this interface if you want to parse OSM documents using the
 * io/parser infrastructure.
 */
class Document {
public:
  /**
   * the ubuquitous virtual destructor.
   */
  virtual ~Document() throw();

  /**
   * this method will be called when a node is emitted with the attributes
   * of the node element and the tags map.
   */
  virtual void node(const tags_t &attrs, const tags_t &tags) = 0;

  /**
   * this method will be called when a way is emitted with the attributes
   * of the way element, the way nodes and the tags map.
   */
  virtual void way(const tags_t &attrs, const std::vector<id_t> &way_nodes, const tags_t &tags) = 0;

  /**
   * this method will be called when a relation is emitted with the attributes
   * of the relation element, the members and the tags map.
   */
  virtual void relation(const tags_t &attrs, const std::list<member> &members, const tags_t &tags) = 0;
};

} }

#endif /* OSM_IO_DOCUMENT_HPP */
