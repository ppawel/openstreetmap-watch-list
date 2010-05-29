#include "osm/member.hpp"
#include "osm/db/owl_diff/tiler.hpp"
#include "osm/db/owl_diff/node.hpp"
#include "osm/db/owl_diff/way.hpp"
#include "osm/db/owl_diff/relation.hpp"
#include "osm/io/extended_database.hpp"
#include <iostream>
#include <sstream>

#define BOOST_TEST_DYN_LINK
#define BOOST_TEST_NO_MAIN
#include <boost/test/unit_test.hpp>

using namespace osm::db::owl_diff;
using std::vector;
using std::ostringstream;
using std::cout;
using std::endl;
using std::string;

namespace {
class test_tiler 
  : public tiler {
public:
  test_tiler() : tiler() {}
  ~test_tiler() throw() {}
  void add_point(const node &n) { tiler::add_point(n); }
  void add_line_between(const node &a, const node &b) { tiler::add_line_between(a, b); }
};

template <typename T>
string to_string(const T &t) {
  ostringstream ostr;
  ostr << t;
  return ostr.str();
}

node make_node(unsigned int id, unsigned int version, unsigned int changeset, double lon, double lat) {
  tags_t tags, attrs;
  attrs["id"] = to_string(id);
  attrs["version"] = to_string(version);
  attrs["changeset"] = to_string(changeset);
  attrs["lat"] = to_string(lat);
  attrs["lon"] = to_string(lon);

  return node(attrs, tags);
}

way make_way(unsigned int id, unsigned int version, unsigned int changeset, id_t *wn) {
  tags_t tags, attrs;
  attrs["id"] = to_string(id);
  attrs["version"] = to_string(version);
  attrs["changeset"] = to_string(changeset);
  vector<id_t> way_nodes;
  for (id_t *wn_itr = wn; *wn_itr != 0; ++wn_itr) {
    way_nodes.push_back(*wn_itr);
  }

  return way(attrs, tags, way_nodes);
}

class test_database 
  : public osm::io::ExtendedDatabase {
public:

  test_database();
  ~test_database() throw();

  bool node(id_t id, tags_t &attrs, tags_t &tags);
  bool way(id_t id, tags_t &attrs, std::vector<id_t> &way_nodes, tags_t &tags);
  bool relation(id_t id, tags_t &attrs, std::list<osm::member> &members, tags_t &tags);
  std::vector<id_t> ways_using_node(id_t id);
};

test_database::test_database() {
}

test_database::~test_database() throw() {
}

bool 
test_database::node(id_t id, tags_t &attrs, tags_t &tags) {
  return false;
}

bool 
test_database::way(id_t id, tags_t &attrs, std::vector<id_t> &way_nodes, tags_t &tags) {
  return false;
}

bool 
test_database::relation(id_t id, tags_t &attrs, std::list<osm::member> &members, tags_t &tags) {
  return false;
}

vector<id_t> 
test_database::ways_using_node(id_t id) {
  return vector<id_t>();
}
}

BOOST_AUTO_TEST_SUITE(Tiler)

BOOST_AUTO_TEST_CASE(node_test) {
  test_tiler t;
  test_database d;

  node n1 = make_node(1, 1, 1, 0.0, 0.0);
  node n2 = make_node(1, 2, 2, 1.0, 1.0);

  n1.diff_tiles(n2, t, d);

  BOOST_CHECK_EQUAL(t.tiles().size(), 2);
}

BOOST_AUTO_TEST_CASE(way_test) {
  test_tiler t;
  test_database d;
  id_t w1_wn[] = {6, 1, 2, 3, 4, 5, 6, 0};
  id_t w2_wn[] = {7, 1, 2, 6, 4, 5, 7, 0};

  way w1 = make_way(1, 1, 1, w1_wn);
  way w2 = make_way(1, 2, 2, w2_wn);

  w1.diff_tiles(w2, t, d);

  BOOST_CHECK_EQUAL(t.tiles().size(), 2);
}

BOOST_AUTO_TEST_SUITE_END()
