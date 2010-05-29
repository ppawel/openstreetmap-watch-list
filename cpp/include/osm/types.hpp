#ifndef OSM_TYPES_HPP
#define OSM_TYPES_HPP

#include <string>
#include <boost/date_time/posix_time/posix_time_types.hpp>
#include <tr1/unordered_map>

// UTF-8 string type
typedef std::string string_t;

// ID type doesn't need to be 64-bit yet, but soon...
typedef unsigned int id_t;
typedef unsigned int version_t;

// tags are a singleton set of (string,string) pairs, well-suited to a
// standard map type. 
typedef std::tr1::unordered_map<string_t, string_t> tags_t;

// ...
typedef boost::posix_time::ptime timestamp_t;

// pack our tiles into 32-bit unsigned ints for the time. should be
// about z16-ish which will be enough for this application.
typedef uint32_t tile_t;

#endif /* OSM_TYPES_HPP */
