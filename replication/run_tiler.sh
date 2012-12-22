#!/bin/bash

cd /home/ppawel/src/openstreetmap-watch-list/scripts

set -e

(
  # Try to lock on the lock file (fd 200)
  flock -x -n 200
  ./tiler.rb --changes
) 200>/home/ppawel/.tiler.lock
