#include "osm/db/dupe_nodes.hpp"
#include "osm/util/quad_tile.hpp"
#include "osm/types.hpp"
#include <iostream>

namespace osm { namespace db {

using std::set;
using std::map;
using std::make_pair;
using std::list;

DupeNodes::DupeNodes(const owl_diff::change_list &c) {
  for (list<owl_diff::change>::const_iterator itr = c.begin();
       itr != c.end(); ++itr) {
    // not interested in elements other than nodes or tag changes, since they can't 
    // change whether a node is a duplicate or not.
    if ((itr->type == owl_diff::change::Node) && (itr->action != owl_diff::change::ChangeTags)) {
      const set<tile_t> &change_tiles = itr->tiles;
      for (set<tile_t>::const_iterator jtr = change_tiles.begin();
	   jtr != change_tiles.end(); ++jtr) {
	// not interested in tiles above 85N or below 85S, as they won't display on 
	// a spherical mercator projection map.
	unsigned int x = 0, y = 0;
	util::tile2xy(*jtr, x, y);
	if ((y < 45738) && (y > 19798)) {
	  map<tile_t, cs_info>::iterator ktr = tiles.find(*jtr);
	  if (ktr == tiles.end()) {
	    tiles.insert(make_pair(*jtr, cs_info(itr->changeset, itr->uid)));
	  } else if (ktr->second.changeset != itr->changeset) {
	    ktr->second.changeset = 0;
	  }
	}
      }
    }
  }
}

DupeNodes::DupeNodes(const set<tile_t> &t) {
  for (set<tile_t>::const_iterator itr = t.begin(); itr != t.end(); ++itr) {
    tiles.insert(make_pair(*itr, cs_info(0, 0)));
  }
}

void
DupeNodes::prepare(pqxx::connection &conn) {
  conn.prepare("clear_tile",
	       "delete from dupe_nodes where tile=$1")
    ("bigint", pqxx::prepare::treat_direct);
  conn.prepare("fill_tile",
	       "insert into dupe_nodes select st_transform(st_setsrid("
	       "st_makepoint(lon/10000000.0, lat/10000000.0), 4326), 900913), "
	       "$1 as tile from (select a.lon, a.lat, count(*) as num from "
	       "nodes a join nodes b on a.lon=b.lon and a.lat=b.lat where "
	       "a.tile=$1 and b.tile=$1 group by a.lon, a.lat) x where num > 1")
    ("bigint", pqxx::prepare::treat_direct);
  conn.prepare("find_changeset",
	       "select count(*) from changesets where id = $1")
    ("bigint", pqxx::prepare::treat_direct);
  conn.prepare("new_changeset",
	       "insert into changesets (id, uid, num) values ($1, $2, $3)")
    ("bigint", pqxx::prepare::treat_direct)
    ("bigint", pqxx::prepare::treat_direct)
    ("bigint", pqxx::prepare::treat_direct);
  conn.prepare("update_changeset",
	       "update changesets set num = num + $2 where id = $1")
    ("bigint", pqxx::prepare::treat_direct)
    ("bigint", pqxx::prepare::treat_direct);
}

void
DupeNodes::operator()(pqxx::work &tx) {
  for (map<tile_t, cs_info>::const_iterator itr = tiles.begin();
       itr != tiles.end(); ++itr) {
    const tile_t tile = itr->first;

    pqxx::result clear_result = tx.prepared("clear_tile")(tile).exec();
    size_t num_cleared = clear_result.affected_rows();

    pqxx::result fill_result = tx.prepared("fill_tile")(tile).exec();
    size_t num_filled = fill_result.affected_rows();

    id_t cs_id = itr->second.changeset;
    if (cs_id > 0) {
      int delta = num_cleared - num_filled;
      pqxx::result find_result = tx.prepared("find_changeset")(cs_id).exec();
      if (find_result[0][0].as<int>() > 0) {
	tx.prepared("update_changeset")(cs_id)(delta).exec();
      } else {
	tx.prepared("new_changeset")(cs_id)(itr->second.uid)(delta).exec();
      }
    }
  }
}

} }
