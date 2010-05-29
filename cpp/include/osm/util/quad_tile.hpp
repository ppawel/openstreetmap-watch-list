#ifndef QUAD_TILE_HPP
#define QUAD_TILE_HPP

#include <cmath>
#include <osm/constants.hpp>

namespace osm { namespace util {

inline unsigned int 
xy2tile(unsigned int x, unsigned int y) {
  x = (x | (x << 8)) & 0x00ff00ff;
  x = (x | (x << 4)) & 0x0f0f0f0f;
  x = (x | (x << 2)) & 0x33333333;
  x = (x | (x << 1)) & 0x55555555;
  
  y = (y | (y << 8)) & 0x00ff00ff;
  y = (y | (y << 4)) & 0x0f0f0f0f;
  y = (y | (y << 2)) & 0x33333333;
  y = (y | (y << 1)) & 0x55555555;
  
  return (x << 1) | y;
}

inline void
tile2xy(unsigned int t, unsigned int &x, unsigned int &y) {
  x = (t >> 1)       & 0x55555555;
  x = (x | (x >> 1)) & 0x33333333;
  x = (x | (x >> 2)) & 0x0f0f0f0f;
  x = (x | (x >> 4)) & 0x00ff00ff;
  x = (x | (x >> 8)) & 0x0000ffff;

  y = t              & 0x55555555;
  y = (y | (y >> 1)) & 0x33333333;
  y = (y | (y >> 2)) & 0x0f0f0f0f;
  y = (y | (y >> 4)) & 0x00ff00ff;
  y = (y | (y >> 8)) & 0x0000ffff;
}

inline unsigned int 
lon2x(int lon) {
  return (lon + (1u << 31)) / (1u << 16);
}

inline unsigned int 
lat2y(int lat) {
  return (lat + (1u << 31)) / (1u << 16);
}

inline unsigned int 
lon2x(double lon) {
  return ((lon * SCALE) + (1u << 31)) / (1u << 16);
}

inline unsigned int 
lat2y(double lat) {
  return ((lat * SCALE) + (1u << 31)) / (1u << 16);
}

}}

#endif /* QUAD_TILE_HPP */
