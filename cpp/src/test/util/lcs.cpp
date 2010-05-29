#include <osm/util/lcs.hpp>
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

vector<id_t>
random_vector() {
  size_t sz = (rand() & 0xff) + 1;
  vector<id_t> vec(sz);

  for (size_t i = 0; i < sz; ++i) {
    vec[i] = rand() & 0xff;
  }

  return vec;
}

ostream &operator<<(ostream &out, const vector<id_t> &v) {
  out << "([" << v.size() << "] ";
  std::copy(v.begin(), v.end(), ostream_iterator<id_t>(out, ", "));
  out << ")";
  return out;
}

void
check_lcs_diff_works(const vector<id_t> &orig_a, const vector<id_t> &b) {
  vector<id_t> c, a(orig_a);

  lcs(a, b, c);
  
  vector<diff_seg> deletions = diff(a, c);
  vector<diff_seg> additions = diff(b, c);
  
  for (vector<diff_seg>::iterator itr = deletions.begin(); itr != deletions.end(); ++itr) {
    a.erase(a.begin() + itr->at, a.begin() + (itr->at + itr->end - itr->start));
  }
  
  BOOST_CHECK_EQUAL(a.size(), c.size());
  BOOST_CHECK(a == c);
  
  size_t inserted = 0;
  for (vector<diff_seg>::iterator itr = additions.begin(); itr != additions.end(); ++itr) {
    a.insert(a.begin() + itr->at + inserted, b.begin() + itr->start, b.begin() + itr->end);
    inserted += itr->end - itr->start;
  }
  
  BOOST_CHECK_EQUAL(a.size(), b.size());
  BOOST_CHECK(a == b);
}

BOOST_AUTO_TEST_SUITE(LCS)

BOOST_AUTO_TEST_CASE(random_test) {
  srand(12456);

  for (int t = 0; t < 1000; ++t) {
    vector<id_t> a = random_vector();
    vector<id_t> b = random_vector();

    check_lcs_diff_works(a, b);
  }
}

BOOST_AUTO_TEST_CASE(reverse_test) {
  const int max_i = 100;
  vector<id_t> a, b;
  for (int i = 0; i < max_i; ++i) {
    a.push_back(i);
    b.push_back(max_i - i - 1);
  }

  check_lcs_diff_works(a, b);
}

BOOST_AUTO_TEST_SUITE_END()

