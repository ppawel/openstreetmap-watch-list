#!/bin/bash

PSQL_OPTIONS=$1
CHANGESET_ID=$2

if [ "$CHANGESET_ID" = "" ]; then
  echo "Usage: dump_testdata.sh <psql_options> <changeset_id>"
  exit 1
fi

psql $PSQL_OPTIONS -c "\copy (SELECT * FROM OWL_GenerateChanges($CHANGESET_ID)) TO '../testdata/$CHANGESET_ID-changes.csv'"
psql $PSQL_OPTIONS -c "\copy (SELECT * FROM tiles WHERE changeset_id = $CHANGESET_ID) TO '../testdata/$CHANGESET_ID-tiles.csv'"
psql $PSQL_OPTIONS -c "\copy (SELECT * FROM changesets WHERE id = $CHANGESET_ID) TO '../testdata/$CHANGESET_ID-changeset.csv'"
