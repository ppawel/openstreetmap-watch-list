#!/bin/bash

cd /home/ppawel/src/openstreetmap-watch-list/tiler

set -e

(
  # Try to lock on the lock file (fd 200)
  flock -x -n 200
  ./owl_tiler.rb &>> ~/tiler.log
) 200>/home/ppawel/.tiler.lock
