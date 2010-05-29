#include <osm/util/quad_tile.hpp>
#include <iostream>

#define BOOST_TEST_DYN_LINK
#define BOOST_TEST_NO_MAIN
#include <boost/test/unit_test.hpp>

using namespace osm::util;
using std::vector;
using std::ostream;
using std::ostream_iterator;
using std::cout;
using std::endl;

namespace {
/**
 * simple method for reversing the morton code to check against the
 * faster, but more complex method implemented in the header file.
 */
inline void
tile2xy2(unsigned int t, unsigned int &x, unsigned int &y) {
  x = y = 0;
  for (int i = 30; i >= 0; i -= 2) {
    x = (x << 1) | ((t >> i) & 0x2); 
    y = (y << 1) | ((t >> i) & 0x1);
  }
  x >>= 1;
}
}

BOOST_AUTO_TEST_SUITE(QuadTile)

BOOST_AUTO_TEST_CASE(random_test) {
  srand(12456);

  for (int t = 0; t < 1000; ++t) {
    unsigned int x = rand() & 0xffff;
    unsigned int y = rand() & 0xffff;

    unsigned int t = xy2tile(x, y);

    unsigned int tx, ty, t2x, t2y;
    tile2xy(t, tx, ty);
    tile2xy2(t, t2x, t2y);
    
    BOOST_CHECK_EQUAL(x, tx);
    BOOST_CHECK_EQUAL(y, ty);
    BOOST_CHECK_EQUAL(x, t2x);
    BOOST_CHECK_EQUAL(y, t2y);
  }
}

BOOST_AUTO_TEST_SUITE_END()
