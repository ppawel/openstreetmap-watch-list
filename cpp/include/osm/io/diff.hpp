#ifndef OSM_IO_DIFF_HPP
#define OSM_IO_DIFF_HPP

#include <osm/types.hpp>
#include <osm/io/document.hpp>
#include <vector>
#include <list>

namespace osm { namespace io {

/**
 * implement this interface if you want to parse OSM diffs using the
 * io/parser infrastructure. this just builds on the document
 * interface by setting the diff type.
 */
class Diff 
  : public Document {
public:
  /**
   * what action to take on the element.
   */
  enum Action {
    Create,
    Modify,
    Delete
  };

  /**
   * change the action type for submitted elements.
   */
  virtual void set_current_action(Action) = 0;
};

} }

#endif /* OSM_IO_DIFF_HPP */
