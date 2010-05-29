#ifndef OSM_IO_API_DATABASE_HPP
#define OSM_IO_API_DATABASE_HPP

#include <osm/io/database.hpp>

namespace osm { namespace io {

class APIDatabase
  : public io::Database {
private:
  std::string api_root;

public:
  APIDatabase();
  explicit APIDatabase(std::string root);

  ~APIDatabase() throw();

  bool node(id_t id, tags_t &attrs, tags_t &tags);

  bool way(id_t id, tags_t &attrs, std::vector<id_t> &way_nodes, tags_t &tags);

  bool relation(id_t id, tags_t &attrs, std::list<member> &members, tags_t &tags);
};

} }

#endif /* OSM_IO_API_DATABASE_HPP */
