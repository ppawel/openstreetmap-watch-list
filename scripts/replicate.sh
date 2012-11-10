#!/bin/bash

# Add osmosis executable to the PATH.
PATH=/home/ppawel/jdk/bin:/home/ppawel/bin:/home/ppawel/.gem/ruby/1.9.1/bin/:$PATH
export PATH

cd /home/ppawel/replication

set -e

(
  # Try to lock on the lock file (fd 200)
  flock -x -n 200
  osmosis -v --rri --lpc --write-owldb-change authFile=~/authFile invalidActionsMode=LOG &>> ~/replication.log
) 200>/home/ppawel/replication/lock
