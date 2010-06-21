#ifndef OSM_UTIL_COMPRESSED_BITSET_HPP
#define OSM_UTIL_COMPRESSED_BITSET_HPP

#include <osm/types.hpp>
#include <set>
#include <vector>
#include <boost/noncopyable.hpp>

namespace osm { namespace util {

/**
 * compressed bitset representation, convertible to set<tile_t>
 */
class CompressedBitset 
  : private boost::noncopyable {
private:
  std::vector<unsigned char> bytes;

public:
  explicit CompressedBitset(const std::set<tile_t> &);
  ~CompressedBitset() throw();
  std::set<tile_t> decompress() const;
  size_t size() const { return bytes.size(); }
};

} }

#endif /* OSM_UTIL_COMPRESSED_BITSET_HPP */
