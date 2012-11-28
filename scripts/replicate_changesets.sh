#!/bin/bash

# Add osmosis executable to the PATH.
PATH=/home/ppawel/jdk/bin:/home/ppawel/bin:/home/ppawel/.gem/ruby/1.9.1/bin/:$PATH
export PATH

DIR=$(dirname $0)
cd $DIR

set -e

(
  # Try to lock on the lock file (fd 200)
  flock -x -n 200
  ./download_changesets.rb &>> ~/changesets.log
) 200>/home/ppawel/.changesets.lock

