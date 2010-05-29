#ifndef OSM_IO_XML_DOCUMENT_READER_HPP
#define OSM_IO_XML_DOCUMENT_READER_HPP

#include "osm/io/document.hpp"
#include "osm/io/diff.hpp"

namespace osm { namespace io {

void read_xml_document(io::Document &doc, const std::string &file_name);
void read_xml_diff(io::Diff &diff, const std::string &file_name);

} }

#endif /* OSM_IO_XML_DOCUMENT_READER_HPP */


