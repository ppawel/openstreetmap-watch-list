#!/bin/bash

YEAR=$1

if [ "$YEAR" = "" ]; then
  echo "Year argument missing!"
  exit 1
fi

wget --level=1 -r -nH --cut-dirs=2 -A.gz http://planet.openstreetmap.org/cc-by-sa/history/$1
