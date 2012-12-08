#!/bin/bash

CHANGESET_ID=$1
PSQL_OPTIONS=$2

if [ "$CHANGESET_ID" = "" ]; then
  echo "Usage: dump_changeset.sh <changeset_id> [psql_options]"
  exit 1
fi

psql $PSQL_OPTIONS -c "\copy (SELECT * FROM OWL_GetChangesetData($CHANGESET_ID)) TO '$CHANGESET_ID.csv'"
