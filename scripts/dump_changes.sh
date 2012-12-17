#!/bin/bash

CHANGESET_ID=$1
PSQL_OPTIONS=$2

if [ "$CHANGESET_ID" = "" ]; then
  echo "Usage: dump_changes.sh <changeset_id> [psql_options]"
  exit 1
fi

psql $PSQL_OPTIONS -c "\copy (SELECT * FROM OWL_GenerateChanges($CHANGESET_ID)) TO '$CHANGESET_ID-changes.csv'"
