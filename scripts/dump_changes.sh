#!/bin/bash

PSQL_OPTIONS=$1
CHANGESET_ID=$2

if [ "$CHANGESET_ID" = "" ]; then
  echo "Usage: dump_changes.sh <psql_options> <changeset_id>"
  exit 1
fi

psql $PSQL_OPTIONS -c "\copy (SELECT * FROM OWL_GenerateChanges($CHANGESET_ID)) TO '$CHANGESET_ID-changes.csv'"
