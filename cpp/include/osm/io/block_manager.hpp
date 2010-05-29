#ifndef OSM_IO_BLOCK_MANAGER_HPP
#define OSM_IO_BLOCK_MANAGER_HPP

#include <map>
#include <list>
#include <string>
#include <memory>

namespace osm { namespace io {

/**
 * manages a bunch of mmap-ed blocks.
 */
class block_manager {
public:

  /**
   * a mmap-ed block. can be closed explicitly, or left open
   * to save some time when coming back to it.
   */
  class block {
  private:
    int fd;
    void *ptr;
    size_t size;
    block_manager &parent;

    block(int f, void *p, size_t s, block_manager &b);
    block(const block &);

    friend class block_manager;
  public:
    ~block() throw();
    void close();
    void *base() const;
  };

  friend class block;

private:

  // max number of fds to open at any one time
  const unsigned int max_open_fds;

  // the fds which are in-use (have a block pointer to them) and
  // are open (don't have a block pointer, but are available)
  std::list<int> used_fds, open_fds;

  // map filenames to fds for open & used so that they can be
  // efficiently re-used.
  std::map<std::string, int> fd_map;

  // unuse a block, moving it to the open chain.
  void unuse(int fd);

  // close a block, removing it from the open chain and freeing the resources.
  void close(int fd);

public:

  // construct with the maximum number of mmappable files.
  explicit block_manager(unsigned int m);

  // destructor will forcably unmap all files
  ~block_manager();

  // open a file and get an RAII block pointer back
  std::auto_ptr<block> open(const std::string &file);
};

}}

#endif /* OSM_IO_BLOCK_MANAGER_HPP */

