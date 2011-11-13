#include <osm/util/compressed_bitset.hpp>
#include <list>
#include <iostream>
#include <cstdio>
#include <vector>
#include <string>

using std::set;
using std::cout;
using std::list;
using std::vector;
using std::auto_ptr;
using std::string;

namespace {

// crit-bit tree structure.
struct tree_entry {
   vector<bool> prefix;
   // either left and right both exist, or neither do.
   auto_ptr<tree_entry> left, right;

   tree_entry(const vector<bool> &b) : prefix(b) {
     assert(prefix.size() <= 32);
   }
   ~tree_entry() throw() {}

   // split this tree entry, or its children to accomodate the new bitstring
   // with iterator range (xtr, xtr_end).
   void split(vector<bool>::const_iterator xtr, vector<bool>::const_iterator xtr_end) {
     vector<bool>::iterator ptr = prefix.begin();
    
     // note that the prefix *can* be zero size, because it isn't necessary to store the 
     // critical bits themselves. in this case we need to skip the comparison stage, and
     // this node should always have children.
     if (!prefix.empty()) {
       while (*xtr == *ptr) {
         ++xtr;
         ++ptr;
         // reaching the the of xtr is a serious error - it means that this string is fully
         // identical to one already in the tree, which shouldn't ever happen in this 
         // use-case.
         if (xtr == xtr_end) {
           throw std::runtime_error("duplicate insertion into crit-bit tree.");
         }
         // reaching the end of ptr just means we need to look at one of our child-trees
         if (ptr == prefix.end()) {
           break;
         }
       }
     }

     if (ptr == prefix.end()) {
       bool is_right = *xtr++;
       // should always be the right fork, because we insert in ascending order?
       assert(is_right);
      
       auto_ptr<tree_entry> &child = is_right ? right : left;
       //assert(child != 0);
       child->split(xtr, xtr_end);
       // and we're all done here.

     } else {
       // now xtr and ptr point to the first different bit between the strings
       // this tree will become everything up to (ptr - 1) inclusive and have two 
       // children, one has the previous children of this node and from (ptr+1) 
       // bits. the other has no children and is (xtr .. xtr_end).
      
       // check that xtr's bit is right - should be the case if we're inserting 
       // in increasing order.
       assert(*xtr == true);
       assert(*ptr == false);

       vector<bool> new_prefix(prefix.begin(), ptr);
       vector<bool> left_prefix(++ptr, prefix.end());
       vector<bool> right_prefix(++xtr, xtr_end);
       assert(new_prefix.size() <= 32);
       assert(left_prefix.size() <= 32);
       assert(right_prefix.size() <= 32);

       auto_ptr<tree_entry> left_child(new tree_entry(left_prefix));
       auto_ptr<tree_entry> right_child(new tree_entry(right_prefix));

       // swap, which cannot fail.
       prefix.swap(new_prefix);
       assert(prefix.size() <= 32);

       // auto pointer assignments, which cannot fail (right?).
       left_child->left = left;
       left_child->right = right;

       left = left_child;
       right = right_child;
     }
   }
};

vector<bool> to_bool_vector(tile_t x) {
  size_t tile_size_in_bits = sizeof(tile_t) * 8;
  vector<bool> vb(tile_size_in_bits);
  //cout << "to_bool_vector(" << x << ") = ";
  for (size_t i = tile_size_in_bits; i > 0; --i) {
    vb[tile_size_in_bits - i] = ((x >> (i - 1)) & 1) == 1;
    //if (vb[tile_size_in_bits - i]) { cout << "1"; } else { cout << "0"; }
  }
  //cout << "\n";
  return vb;
}

tile_t from_bool_vector(const vector<bool> &vb) {
  tile_t x = 0;
  for (vector<bool>::const_iterator itr = vb.begin(); itr != vb.end(); ++itr) {
    x <<= 1;
    if (*itr) x |= 1;
  }
  return x;
}

auto_ptr<tree_entry> build_crit_bit_tree(const set<tile_t> &tiles) {
  auto_ptr<tree_entry> root;
  for (set<tile_t>::const_iterator itr = tiles.begin(); itr != tiles.end(); ++itr) {
    vector<bool> vb = to_bool_vector(*itr);
    if (root.get() != 0) {
      //cout << "adding " << *itr << " to tree as split\n";
      root->split(vb.begin(), vb.end());
    } else {
      //cout << "building tree as new from " << *itr << "\n";
      root = auto_ptr<tree_entry>(new tree_entry(vb));
    }
  }
  return root;
}

set<tile_t> unbuild_crit_bit_tree(auto_ptr<tree_entry> root, int n) {
  set<tile_t> s;
  if (root->left.get() == 0 || root->right.get() == 0) {
    // end, so this is just a singleton which is known to end in the least 
    // significant bit. therefore no shifting is required.
    s.insert(from_bool_vector(root->prefix));

  } else {
    // not the end - have to take the children and add the prefix bits to them,
    // and add the left/right bits depending on which child they came from.
    int child_n = n - (root->prefix.size() + 1);
    set<tile_t> left = unbuild_crit_bit_tree(root->left, child_n); 
    set<tile_t> right = unbuild_crit_bit_tree(root->right, child_n);

    tile_t prefix = from_bool_vector(root->prefix);
    tile_t left_prefix = ((prefix << 1) | 0) << child_n;
    tile_t right_prefix = ((prefix << 1) | 1) << child_n;

    for (set<tile_t>::iterator itr = left.begin(); itr != left.end(); ++itr) {
      s.insert(*itr | left_prefix);
    }
    for (set<tile_t>::iterator itr = right.begin(); itr != right.end(); ++itr) {
      s.insert(*itr | right_prefix);
    }
  }
  return s;
}

typedef std::pair<vector<bool>::const_iterator, size_t> prefix_parse_t;

/* the following two functions serialise and deserialise the prefix length, which in a naive 
 * implementation would be 6 bits to represent the size of a 32-bit tile_t. however, since in
 * the real world use-cases of this for morton-encoded geographic entities the most common
 * prefix sizes are those which are much lower it seems better to use a huffman-style encoding
 * such as:
 *
 * prefix length | code      | code length   
 * --------------+-----------+------------
 *       0       | 0         | 1
 *      1-2      | 10*       | 3
 *      3-6      | 110**     | 5
 *      7-14     | 1110***   | 7
 *     15-30     | 11110**** | 9
 *     31-32     | 11111*    | 6
 *
 * using this prefix encoding gets a random-fixed-prefix test case size down by 58% versus an
 * array of uint32_t's. using the "snake" test case, which is more realistic for geometric
 * use-cases, it compresses by about 82%.
 */
#define PREFIX_CODING

#ifdef PREFIX_CODING
vector<bool> prefix_size_to_bits(size_t x) {
  vector<bool> rv;
#define PREFIX_WITH(n) { for (int i = 0; i < (n); ++i) { rv.push_back(true); }; rv.push_back(false); }
  rv.reserve(9);
  if (x == 0) {
    PREFIX_WITH(0);
  } else if (x < 3) {
    PREFIX_WITH(1);
    rv.push_back(x == 2);
  } else if (x < 7) {
    PREFIX_WITH(2);
    rv.push_back(((x - 3) & 2) == 2);
    rv.push_back(((x - 3) & 1) == 1);
  } else if (x < 15) {
    PREFIX_WITH(3);
    rv.push_back(((x - 7) & 4) == 4);
    rv.push_back(((x - 7) & 2) == 2);
    rv.push_back(((x - 7) & 1) == 1);
  } else if (x < 31) {
    PREFIX_WITH(4);
    rv.push_back(((x - 15) & 8) == 8);
    rv.push_back(((x - 15) & 4) == 4);
    rv.push_back(((x - 15) & 2) == 2);
    rv.push_back(((x - 15) & 1) == 1);
  } else {
    for (int i = 0; i < 5; ++i) { rv.push_back(true); }
    rv.push_back(x == 32);
  }
  return rv;
#undef PREFIX_WITH
}

prefix_parse_t bits_to_prefix_size(vector<bool>::const_iterator bits, vector<bool>::const_iterator bits_end) {
  bool bit;
  size_t size = 0;
#define GET_BIT { if (bits == bits_end) throw std::runtime_error("Unexpected end of bit-string during prefix length reading."); bit = *bits++; }
  GET_BIT;
  if (bit == true) {
    GET_BIT;
    if (bit == true) {
      GET_BIT;
      if (bit == true) {
        GET_BIT;
        if (bit == true) {
          GET_BIT;
          if (bit == true) {
            GET_BIT;
            size = bit ? 32 : 31;

          } else {
            GET_BIT; size_t x = bit ? 1 : 0;
            GET_BIT; x = (x << 1) | bit;
            GET_BIT; x = (x << 1) | bit;
            GET_BIT; x = (x << 1) | bit;
            size = 15 + x;
          }

        } else {
          GET_BIT; size_t x = bit ? 1 : 0;
          GET_BIT; x = (x << 1) | bit;
          GET_BIT; x = (x << 1) | bit;
          size = 7 + x;
        }

      } else {
        GET_BIT; size_t x = bit ? 1 : 0;
        GET_BIT; x = (x << 1) | bit;
        size = 3 + x;
      }

    } else {
      GET_BIT;
      size = bit ? 2 : 1;
    }
  }

  return std::make_pair(bits, size);
#undef GET_BIT
}

#else /* PREFIX_CODING */
/* old naive implementation
 */
vector<bool> prefix_size_to_bits(size_t x) {
  vector<bool> prefix_len = to_bool_vector(x);
  //assert(prefix_len.size() == 32);
  prefix_len.erase(prefix_len.begin(), prefix_len.begin() + (32 - 6));
  //assert(prefix_len.size() == 6);
  return prefix_len;
}

prefix_parse_t bits_to_prefix_size(vector<bool>::const_iterator bits, vector<bool>::const_iterator bits_end) {
  // read 6 bits for the size of the prefix
  size_t prefix_size = 0;
  for (size_t i = 0; i < 6; ++i) { 
    prefix_size <<= 1;
    if (bits == bits_end) { throw std::runtime_error("Unexpected end of bit-string during prefix length reading."); }
    if (*bits++) { 
      prefix_size |= 1; 
    } 
  }

  return std::make_pair(bits, prefix_size);
}

#endif /* PREFIX_CODING */

vector<bool> serialise_to_bit_vector(const auto_ptr<tree_entry> &node) {
  vector<bool> rv;
  if (node.get() != 0) {
    // output the prefix length - but we only need 6 bits for a 32-bit tile_t size
    // we need 6 because the length could be zero up to and *including* 32 same bits.
    // given that this only happens with a single element set, it might be worth
    // making a special exception in that case.
    // TODO: make a little bit more platform independent!
    //cout << "prefix length: " << node->prefix.size() << "\n";
    vector<bool> prefix_len = prefix_size_to_bits(node->prefix.size());
    rv.insert(rv.end(), prefix_len.begin(), prefix_len.end());
    rv.insert(rv.end(), node->prefix.begin(), node->prefix.end());
    
    // get and output the left and right trees
    vector<bool> left = serialise_to_bit_vector(node->left);
    rv.insert(rv.end(), left.begin(), left.end());

    vector<bool> right = serialise_to_bit_vector(node->right);
    rv.insert(rv.end(), right.begin(), right.end());
  }
  return rv;
}

// returns a pair of the next bit to read and the tree that got parsed from it
struct parse_result {
   parse_result(vector<bool>::const_iterator pp, auto_ptr<tree_entry> t) : parse_point(pp), tree(t) {}
   parse_result(parse_result &other) : parse_point(other.parse_point), tree(other.tree) {}
   parse_result(const parse_result &other) : parse_point(other.parse_point), tree(const_cast<parse_result &>(other).tree) {}
   vector<bool>::const_iterator parse_point;
   auto_ptr<tree_entry> tree;
};

parse_result
deserialise_from_bit_vector(vector<bool>::const_iterator bits, vector<bool>::const_iterator bits_end, int n) {
  prefix_parse_t prefix_parse = bits_to_prefix_size(bits, bits_end);
  bits = prefix_parse.first;
  size_t prefix_size = prefix_parse.second;

  // read the prefix
  vector<bool> prefix;
  if (prefix_size > 0) {
    prefix.reserve(prefix_size);
    for (size_t i = 0; i < prefix_size; ++i) { 
      if (bits == bits_end) { throw std::runtime_error("Unexpected end of bit-string during prefix reading."); }
      prefix.push_back(*bits++); 
    }
  }

  auto_ptr<tree_entry> rv(new tree_entry(prefix));
  size_t child_n = n - prefix_size;

  // check if there are any left or right trees to read
  if (child_n > 0) {
    // read the left and right trees (each of which elides a bit, so that has to be added on)
    parse_result left_result = deserialise_from_bit_vector(bits, bits_end, child_n - 1);
    bits = left_result.parse_point;
    parse_result right_result = deserialise_from_bit_vector(bits, bits_end, child_n - 1);
    
    // construct the tree
    rv->left = left_result.tree;
    rv->right = right_result.tree;

    return parse_result(right_result.parse_point, rv);

  } else {
    return parse_result(bits, rv);
  }
}

auto_ptr<tree_entry> deserialise_from_bit_vector(const vector<bool> &vb) {
  parse_result result = deserialise_from_bit_vector(vb.begin(), vb.end(), sizeof(tile_t) * 8);
  return result.tree;
}

vector<unsigned char> serialise(const auto_ptr<tree_entry> &node) {
  vector<bool> vb = serialise_to_bit_vector(node);
  vector<unsigned char> rv;
  rv.reserve(vb.size() / 8 + 1); // probably how many bytes will be needed
  unsigned char reg = 0;
  int bits_left = 8;
  //cout << "serialise: ";
  for (vector<bool>::iterator itr = vb.begin(); itr != vb.end(); ++itr) {
    //if (*itr) { cout << "1"; } else { cout << "0"; }
    --bits_left;
    if (*itr) { reg |= 1 << bits_left; }
    if (bits_left == 0) {
      rv.push_back(reg);
      bits_left = 8;
      reg = 0;
    }
  }
  //cout << "\n";
  if (bits_left != 8) {
    rv.push_back(reg);
  }
  return rv;
}

auto_ptr<tree_entry> deserialise(const vector<unsigned char> &bytes) {
  vector<bool> rv;
  rv.reserve(bytes.size() * 8);
  for (vector<unsigned char>::const_iterator itr = bytes.begin(); itr != bytes.end(); ++itr) {
    unsigned char x = *itr;
    rv.push_back((x & 0x80) > 0);
    rv.push_back((x & 0x40) > 0);
    rv.push_back((x & 0x20) > 0);
    rv.push_back((x & 0x10) > 0);
    rv.push_back((x & 0x08) > 0);
    rv.push_back((x & 0x04) > 0);
    rv.push_back((x & 0x02) > 0);
    rv.push_back((x & 0x01) > 0);
  }
  // note - there are going to be some superfluous bits on the end of this array, but the
  // rest of the deserialisation process should be able to safely ignore them.
  return deserialise_from_bit_vector(rv);
}

set<tile_t> directions_with_prefix(tile_t match_prefix, int i, const set<tile_t> &s) {
  set<tile_t> directions;
  for (set<tile_t>::const_iterator itr = s.begin(); itr != s.end(); ++itr) {
    tile_t tile = *itr;
    tile_t prefix = tile >> (2 * i);
    //cout << "if " << tile << " matches " << (prefix >> 2) << " << " << i << " then " << ((tile >> (2 * i)) & 3) << "\n";
    if ((prefix >> 2) == match_prefix)
       directions.insert(prefix & 3);
  }
  return directions;
}

list<char> recurse(tile_t match_prefix, int i, const set<tile_t> &s) {
  set<tile_t> directions = directions_with_prefix(match_prefix, i, s);
  list<char> l;
  char x = 0;
  for (set<tile_t>::iterator itr = directions.begin(); itr != directions.end(); ++itr) {
    x |= (1 << *itr);
  }
  l.push_back(x);
  if (i > 0) {
    for (set<tile_t>::iterator itr = directions.begin(); itr != directions.end(); ++itr) {
      list<char> rv = recurse((match_prefix << 2) | *itr, i - 1, s);
      l.splice(l.end(), rv);
    }
  }
  return l;
}

}

namespace osm { namespace util {

CompressedBitset::CompressedBitset(const string &s) {
  bytes.reserve(s.size());
  for (string::const_iterator itr = s.begin(); itr != s.end(); ++itr) {
    bytes.push_back((unsigned char)(*itr));
  }
}

CompressedBitset::CompressedBitset(const set<tile_t> &s) {
  auto_ptr<tree_entry> root = build_crit_bit_tree(s);
  bytes = serialise(root);
  // printf("serialised as %ld bytes, array would be %ld bytes: ", data.size(), s.size() * sizeof(tile_t));
  // for (vector<unsigned char>::iterator itr = data.begin(); itr != data.end(); ++itr) {
  //   printf("%02x ", int(*itr));
  // }
  // printf("\n");
}

CompressedBitset::~CompressedBitset() throw() {
}

set<tile_t>
CompressedBitset::decompress() const {
  auto_ptr<tree_entry> root = deserialise(bytes);
  return unbuild_crit_bit_tree(root, sizeof(tile_t) * 8);
}

string
CompressedBitset::str() const {
  string s(bytes.size(), '\0');
  for (size_t i = 0; i < bytes.size(); ++i) {
    s[i] = (char)bytes[i];
  }
  return s;
}

} }

