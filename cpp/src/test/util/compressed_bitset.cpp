#include <osm/util/compressed_bitset.hpp>
#include <osm/util/quad_tile.hpp>
#include <iostream>

#define BOOST_TEST_DYN_LINK
#define BOOST_TEST_NO_MAIN
#include <boost/test/unit_test.hpp>

using namespace osm::util;
using std::set;
using std::ostream;
using std::cout;
using std::endl;

set<tile_t> random_set() {
  set<tile_t> s;
  for (int i = 0; i < 500; ++i) {
    tile_t tile = rand() & 0xffff;
    s.insert(tile);
  }
  return s;
}

set<tile_t> snake_set() {
  unsigned int x, y;
  x = rand() & 0xffff;
  y = rand() & 0xffff;
  set<tile_t> s;
  for (int i = 0; i < 500; ++i) {
    tile_t tile = xy2tile(x, y);
    s.insert(tile);
    int r = rand();
    if ((r & 1) > 0) { x += 1; } else { y += 1; }
  }
  return s;  
}

BOOST_TEST_DONT_PRINT_LOG_VALUE( set<tile_t> )

BOOST_AUTO_TEST_SUITE(compressed_bitset)

BOOST_AUTO_TEST_CASE(single_entry_set) {
  set<tile_t> a;
  a.insert(0xaaaaaaaal); // nice pretty 10101010 pattern
  CompressedBitset c(a);
  set<tile_t> b = c.decompress();
  BOOST_CHECK_EQUAL(a, b);
}

BOOST_AUTO_TEST_CASE(double_entry_set) {
  set<tile_t> a;
  a.insert(0xaaaaaaaal); // nice pretty 10101010 pattern
  a.insert(0xaaaa5555l); // but this only shares half those bits
  CompressedBitset c(a);
  set<tile_t> b = c.decompress();
  BOOST_CHECK_EQUAL(a, b);
}

BOOST_AUTO_TEST_CASE(triple_entry_set) {
  set<tile_t> a;
  a.insert(0xaaaaaaaal); 
  a.insert(0xaaaa5555l); 
  a.insert(0xaaaa55aal); 
  CompressedBitset c(a);
  set<tile_t> b = c.decompress();
  BOOST_CHECK_EQUAL(a, b);
}

BOOST_AUTO_TEST_CASE(random_test) {
  srand(12456);
  size_t set_bytes = 0, compressed_bytes = 0;

  for (int i = 0; i < 100; ++i) {
    set<tile_t> a = random_set();
    CompressedBitset c(a);

    set_bytes += a.size() * sizeof(tile_t);
    compressed_bytes += c.size();

    set<tile_t> b = c.decompress();
    BOOST_CHECK_EQUAL(a, b);
  }

  cout << "random: " << set_bytes << ", " << compressed_bytes << "\n";
}

BOOST_AUTO_TEST_CASE(snake_test) {
  srand(12456);
  size_t set_bytes = 0, compressed_bytes = 0;

  for (int i = 0; i < 100; ++i) {
    set<tile_t> a = snake_set();
    CompressedBitset c(a);

    set_bytes += a.size() * sizeof(tile_t);
    compressed_bytes += c.size();

    set<tile_t> b = c.decompress();
    BOOST_CHECK_EQUAL(a, b);
  }

  cout << "snake: " << set_bytes << ", " << compressed_bytes << "\n";
}

BOOST_AUTO_TEST_SUITE_END()
