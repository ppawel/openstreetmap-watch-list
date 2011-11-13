#ifndef OSM_UTIL_LCS_HPP
#define OSM_UTIL_LCS_HPP

#include <vector>
#include <osm/types.hpp>

namespace osm { namespace util {

/**
 * compute the longest common subsequence of xs and ys, putting the
 * result into an_lcs.
 */
void lcs(const std::vector<id_t> &xs, 
         const std::vector<id_t> &ys, 
         std::vector<id_t> &an_lcs);

/**
 * a segment of the diff
 */
struct diff_seg {
   // in a diff between A and B, where B is the common subsequence...
   size_t at; // the index to insert before in B.
   size_t start, end; // the indices start to end in A, end exclusive.

   diff_seg(size_t a, size_t b, size_t c);
};

/**
 * difference between a sequence A and a subsequence of that, B, returning
 * the array of differences.
 */
std::vector<diff_seg> diff(const std::vector<id_t> &a, const std::vector<id_t> &b);

} }

#endif /* OSM_UTIL_LCS_HPP */
