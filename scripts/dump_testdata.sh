#!/bin/bash

PSQL_OPTIONS=$1
CHANGESET_ID=$2

if [ "$CHANGESET_ID" = "" ]; then
  echo "Usage: dump_testdata.sh <psql_options> <changeset_id>"
  exit 1
fi

psql $PSQL_OPTIONS -a -c "\copy (SELECT * FROM changesets WHERE id = $CHANGESET_ID) TO '../testdata/$CHANGESET_ID-changeset.csv'"

psql $PSQL_OPTIONS -a -c "\copy ( \
  WITH way_ids AS \
    (SELECT id FROM ways WHERE nodes && (SELECT array_agg(id) FROM nodes WHERE changeset_id = $CHANGESET_ID) UNION \
    SELECT id FROM ways WHERE changeset_id = $CHANGESET_ID), \
  node_data AS (SELECT * FROM nodes WHERE changeset_id = $CHANGESET_ID \
    UNION SELECT * FROM nodes WHERE id IN (SELECT unnest(nodes) FROM ways WHERE id IN (SELECT id FROM way_ids) )) \
  (SELECT n.* FROM nodes n WHERE n.id IN (SELECT id FROM node_data)) \
    ORDER BY id, version \
  ) TO '../testdata/$CHANGESET_ID-nodes.csv'"

psql $PSQL_OPTIONS -a -c "\copy ( \
  WITH way_ids AS (SELECT id FROM ways WHERE changeset_id = $CHANGESET_ID UNION \
      SELECT id FROM ways WHERE nodes && (SELECT array_agg(id) FROM nodes WHERE changeset_id = $CHANGESET_ID)) \
   (SELECT w.* FROM ways w WHERE w.id IN (SELECT id FROM way_ids)) \
   ORDER BY id, version \
  ) TO '../testdata/$CHANGESET_ID-ways.csv'"
