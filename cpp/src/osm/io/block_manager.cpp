#include "osm/io/block_manager.hpp"
#include <algorithm>
#include <sstream>
#include <cerrno>
#include <stdexcept>

#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <string.h>

using namespace std;

namespace osm { namespace io {

block_manager::block::block(int f, void *p, block_manager &b)
  : fd(f), ptr(p), parent(b) {
}

block_manager::block::~block() throw() {
  ptr = NULL;
  parent.unuse(fd);
}

void 
block_manager::block::close() {
  ptr = NULL;
  parent.close(fd);
}

void *
block_manager::block::base() const {
  return ptr;
}

// unuse a block, moving it to the open chain.
void 
block_manager::unuse(int fd) {
  list<int>::iterator itr = find(used_fds.begin(), used_fds.end(), fd);
  if (itr != used_fds.end()) {
    open_fds.push_back(fd);
    used_fds.erase(itr);
  }
}

void
block_manager::close(int fd) {
  list<int>::iterator itr = find(open_fds.begin(), open_fds.end(), fd);
  if (itr != used_fds.end()) {
    // EARGH. need to fix this.
    ::close(fd);
    open_fds.erase(itr);
  }
}

// construct with the maximum number of mmappable files.
block_manager::block_manager(unsigned int m)
  : max_open_fds(m) {
}

// destructor will forceably unmap all files
block_manager::~block_manager() {
  for (list<int>::iterator itr = used_fds.begin(); itr != used_fds.end(); ++itr) {
    unuse(*itr);
  }
  for (list<int>::iterator itr = open_fds.begin(); itr != open_fds.end(); ++itr) {
    close(*itr);
  }
}

// open a file and get an RAII block pointer back
std::auto_ptr<block_manager::block> 
block_manager::open(const std::string &file) {
  if (used_fds.size() >= max_open_fds) {
    throw runtime_error("Too many mmap()ed files.");
  }

  map<string, int>::iterator lookup_itr = fd_map.find(file);
  if (lookup_itr == fd_map.end()) {
    int fd = ::open(file.c_str(), O_RDWR);
    if (fd < 0) {
      ostringstream ostr;
      ostr << "Trying to open file `" << file << "', but got error: " << strerror(errno);
      throw runtime_error(ostr.str());
    }
    
    struct stat buf;
    int status = ::fstat(fd, &buf);
    if (status < 0) {
      ostringstream ostr;
      ostr << "Trying to stat file `" << file << "', but got error: " << strerror(errno);
      throw runtime_error(ostr.str());
    }
    
    void *ptr = ::mmap(NULL, buf.st_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (ptr == MAP_FAILED) {
      ostringstream ostr;
      ostr << "Trying to open file `" << file << "', but got error: " << strerror(errno);
      throw runtime_error(ostr.str());
    }
    
    if (used_fds.size() + open_fds.size() >= max_open_fds) {
      open_fds.erase(open_fds.begin());
    }
    used_fds.push_back(fd);
    fd_map[file] = fd;
    
    return auto_ptr<block>(new block(fd, ptr, buf.st_size, *this));
  }
}

}}
