#include <osm/db/owl_loader.hpp>
#include <osm/db/owl_database.hpp>
#include <osm/db/owl_diff.hpp>
#include <osm/io/xml_document_reader.hpp>
#include <iostream>
#include <pqxx/pqxx>

#define BOOST_TEST_DYN_LINK
#define BOOST_TEST_NO_MAIN
#include <boost/test/unit_test.hpp>

using std::set;
using std::ostream;
using std::cout;
using std::endl;
using std::string;

namespace {

// load a "planet" file into the database. note: truncates most db tables as it goes.
void load_planet(pqxx::connection &conn, const string &planet_file) {
  osm::db::OWLLoader loader(conn, 100000);
  osm::io::read_xml_document(loader, planet_file);
  loader.finish();
}

// load a "diff" file into the database.
void load_diff(pqxx::connection &conn, const string &diff_file) {
  osm::db::OWLDatabase database(conn);
  osm::db::OWLDiff diff(database, osm::db::OWLDiff::DebugMode);
  osm::io::read_xml_diff(diff, diff_file);
  diff.finish();
  database.finish();  
}

}

BOOST_TEST_DONT_PRINT_LOG_VALUE( set<tile_t> )

BOOST_AUTO_TEST_SUITE(way_tile_cache)

BOOST_AUTO_TEST_CASE(simple_one_way_change) {
  pqxx::connection conn("dbname=owl_test");
  load_planet(conn, "test_files/simple_one_way_change.planet.osm");
  load_diff(conn, "test_files/simple_one_way_change.osc");
  // not really a proper test case yet - but the answer should be that tiles
  // 1811868936, 1811868938 and 1811868939 get cached by the way in the DB.
}

BOOST_AUTO_TEST_SUITE_END()
