#include "osm/db/dupe_nodes.hpp"
#include "osm/util/quad_tile.hpp"
#include <stdexcept>
#include <iostream>
#include <boost/program_options.hpp>

using namespace std;
namespace po = boost::program_options;

set<tile_t>
find_all_tiles(pqxx::connection &conn) {
  pqxx::nontransaction work(conn, "getting_tiles");
  const tile_t min_tile = work.exec("select min(tile) from nodes")[0][0].as<tile_t>();
  const tile_t max_tile = work.exec("select max(tile) from nodes")[0][0].as<tile_t>();
  const tile_t delta_tile = (max_tile - min_tile) >> 9;
  set<tile_t> tiles;

  for (tile_t range = min_tile; range < max_tile; range += delta_tile) {
    std::stringstream query;
    query << "select distinct tile from nodes where tile between " << range << " and " << range + delta_tile;
    std::cout << query.str() << std::endl;
    pqxx::icursorstream stream(work, query.str(), "all_tiles", 10000);

    const pqxx::icursor_iterator end;
    for (pqxx::icursor_iterator itr(stream); itr != end; ++itr) {
      for (pqxx::result::const_iterator jtr = itr->begin(); jtr != itr->end(); ++jtr) {
        tile_t tile = (tile_t)((*jtr)["tile"].as<tile_t>());
        tiles.insert(tile);
      }
    }
  }

  return tiles;
}

bool
does_tile_exist(pqxx::connection &conn, tile_t tile) {
  pqxx::nontransaction check(conn, "checking_exist");
  ostringstream ostr;
  ostr << "select count(*) from dupe_nodes where tile = " << tile;
  pqxx::result res = check.exec(ostr.str());
  int n = res[0][0].as<int>();
  return n > 0;
}

int
main(int argc, char *argv[]) {
  string db;
  tile_t tile = 0;
  bool force, find_tiles = true;

  po::options_description desc("OWL uploader");
  desc.add_options()
     ("help,h", "This help message.")
     ("tile,t", po::value<tile_t>(&tile), 
      "Tile to recalculate.")
     ("force,f", po::value<bool>(&force)->default_value(false), 
      "Force a recalculation, even if the tile has been calculated already.")
     ("db,d", po::value<string>(&db)->default_value("dbname=owl"), 
      "Database connection string")
     ;

  po::variables_map vm;
  po::store(po::command_line_parser(argc, argv)
            .options(desc)
            .run(), vm);
  po::notify(vm);

  if (vm.count("help")) {
    cout << desc << "\n";
    return 1;
  }

  if (vm.count("tile") > 0) {
    find_tiles = false;
  }

  try {
    pqxx::connection conn(db);

    set<tile_t> tiles;
    if (find_tiles) {
      cout << "finding tiles ..." << endl;
      tiles = find_all_tiles(conn);
    } else {
      tiles.insert(tile);
    }

    size_t counter = 0, last_counter = 0, num_tiles = tiles.size();
    cout << "about to update " << num_tiles << " tiles" << endl;
    for (set<tile_t>::iterator itr = tiles.begin(); itr != tiles.end(); ++itr) {
      try {
        // not interested in tiles above 85N or below 85S, as they won't display on 
        // a spherical mercator projection map.
        unsigned int x = 0, y = 0;
        osm::util::tile2xy(*itr, x, y);
        if ((y < 45738) && (y > 19798)) {
          if (force || !does_tile_exist(conn, *itr)) {
            set<tile_t> single_tile;
            single_tile.insert(*itr);
            osm::db::DupeNodes dn(single_tile);
            dn.prepare(conn);
            conn.perform(dn);
            if (counter > last_counter + 1000) {
              cout << "updating tile " << *itr << " (" << 100 * double(counter) / double(num_tiles) << "%)" << endl;
              last_counter = counter;
            }
          }
        }
      } catch (std::exception &e) {
        cerr << "error during tile " << *itr << endl;
        throw;
      }
      ++counter;
    }

    cout << "Success!\n";
    return 0;

  } catch (const exception &e) {
    cerr << "ERROR\n";
    cerr << e.what() << endl;
    return 1;

  } catch (...) {
    cerr << "UNKNOWN EXCEPTION\n";
    return 1;
  }

  return 2;
}
