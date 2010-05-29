#include "osm/member.hpp"

namespace osm {

member::member(const member &m)
  : id(m.id), role(m.role), type(m.type) {
}
member::member(id_t id_, const std::string &role_, const std::string &type_)
  : id(id_), role(role_), type(type_) {
}
const member &
member::operator=(const member &m) {
  id = m.id;
  role = m.role;
  type = m.type;
  return *this;
}

bool 
member::operator==(const member &m) const {
  return (id == m.id) && (role == m.role) && (type == m.type);
}

bool 
member::operator!=(const member &m) const {
  return !operator==(m);
}

}
