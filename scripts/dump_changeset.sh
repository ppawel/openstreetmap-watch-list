#!/bin/bash

CHANGESET_ID=$1
PSQL_OPTIONS=$2

if [ "$CHANGESET_ID" = "" ]; then
  echo "Usage: dump_changeset.sh <changeset_id> [psql_options]"
  exit 1
fi

psql $PSQL_OPTIONS -c "\copy (SELECT * FROM changesets WHERE id = $CHANGESET_ID) TO 'changeset_$CHANGESET_ID.csv'"
psql $PSQL_OPTIONS -c "\copy (SELECT * FROM changes WHERE changeset_id = $CHANGESET_ID) TO 'changes_$CHANGESET_ID.csv'"
