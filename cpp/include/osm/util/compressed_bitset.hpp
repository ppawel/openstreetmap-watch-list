#ifndef OSM_UTIL_COMPRESSED_BITSET_HPP
#define OSM_UTIL_COMPRESSED_BITSET_HPP

#include <osm/types.hpp>
#include <set>
#include <vector>

namespace osm { namespace util {

/**
 * compressed bitset representation, convertible to set<tile_t>
 */
class CompressedBitset {
private:
  std::vector<unsigned char> bytes;

public:
  // construct from compressed representation
  explicit CompressedBitset(const std::string &);

  // construct from set of tile IDs
  explicit CompressedBitset(const std::set<tile_t> &);

  ~CompressedBitset() throw();
  std::set<tile_t> decompress() const;
  size_t size() const { return bytes.size(); }
  std::string str() const;
};

} }

#endif /* OSM_UTIL_COMPRESSED_BITSET_HPP */
