#ifndef OSM_MEMBER_HPP
#define OSM_MEMBER_HPP

#include <osm/types.hpp>
#include <string>

namespace osm {
  
/**
 * very simple member container type to feed relations.
 */
struct member {
  id_t id; // note: the id of the *member*
  std::string role, type;
  
  member(const member &m);
  member(id_t id_, const std::string &role_, const std::string &type_);
  const member &operator=(const member &m);
  bool operator==(const member &m) const;
  bool operator!=(const member &m) const;
private:
  member();
};

}

#endif /* OSM_MEMBER_HPP */
