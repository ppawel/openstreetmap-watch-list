#!/bin/bash

AUTH_FILE=$1
OSC_FILE=$2

if [ "$AUTH_FILE" = "" ]; then
        echo "Auth file argument missing!"
       	echo "Usage: process_osc_file.sh <Osmosis auth file> <osc file>"
	exit 1
fi

if [ "$OSC_FILE" = "" ]; then
        echo "OSC file argument missing!"
	echo "Usage: process_osc_file.sh <Osmosis auth file> <osc file>"
        exit 1
fi

osmosis --read-xml-change $OSC_FILE --tee-change --write-changedb-change authFile=$AUTH_FILE --log-progress-change --write-pgsql-change authFile=$AUTH_FILE

