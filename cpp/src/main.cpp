#include "osm/io/xml_document_reader.hpp"
#include "osm/db/owl_loader.hpp"
#include "osm/db/owl_database.hpp"
#include "osm/db/owl_diff.hpp"
#include "osm/db/dupe_nodes.hpp"
#include <stdexcept>
#include <iostream>
#include <boost/program_options.hpp>

using namespace std;
namespace po = boost::program_options;

int
main(int argc, char *argv[]) {
  string file, db;
  bool planet_mode = false, dupe_nodes = false;
  osm::db::OWLDiff::Mode debug_mode = osm::db::OWLDiff::NormalMode;

  po::options_description desc("OWL uploader");
  desc.add_options()
    ("help,h", "This help message.")
    ("planet,p", "Import a planet (rather than a diff).")
    ("dry-run,n", "Dry-run (print changes, don't commit them).")
    ("db,d", po::value<string>(&db)->default_value("dbname=owl"), 
     "Database connection string")
    ("file,f", po::value<string>(&file), "File to import.")
    ("dupe-nodes,u", "Update the dupe nodes table.")
    ;

  po::positional_options_description pos;
  pos.add("file", 1);
  po::variables_map vm;
  po::store(po::command_line_parser(argc, argv)
	    .options(desc)
	    .positional(pos)
	    .run(), vm);
  po::notify(vm);

  if (vm.count("planet")) {
    planet_mode = true;
  }

  if (vm.count("dry-run")) {
    debug_mode = osm::db::OWLDiff::DebugMode;
  }

  if (vm.count("help")) {
    cout << desc << "\n";
    return 1;
  }

  if (vm.count("dupe-nodes")) {
    dupe_nodes = true;
  }

  try {
    pqxx::connection conn(db);

    if (planet_mode) {
      osm::db::OWLLoader loader(conn, 100000);
      osm::io::read_xml_document(loader, file);
      loader.finish();

    } else {
      osm::db::OWLDatabase database(conn);
      osm::db::OWLDiff diff(database, debug_mode);
      osm::io::read_xml_diff(diff, file);
      diff.finish();
      if (debug_mode != osm::db::OWLDiff::DebugMode) {
	database.finish();
      }
      if (dupe_nodes) {
	osm::db::DupeNodes dn(diff.changes_list());
	dn.prepare(conn);
	conn.perform(dn);
      }
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
