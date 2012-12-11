﻿DROP FUNCTION IF EXISTS OWL_MakeLine(bigint[], timestamp without time zone);
DROP FUNCTION IF EXISTS OWL_GetChangesetData(int);
DROP FUNCTION IF EXISTS OWL_UpdateChangeset(bigint);
DROP FUNCTION IF EXISTS OWL_AggregateChangeset(bigint, int, int);

--
-- OWL_MakeLine
--
-- Creates a linestring from given list of node ids. If timestamp is given,
-- the node versions used are filtered by this timestamp (are no newer than).
-- This is useful for creating way geometry for historic versions.
--
CREATE FUNCTION OWL_MakeLine(bigint[], timestamp without time zone) RETURNS geometry(LINESTRING, 4326) AS $$
  SELECT ST_MakeLine(geom)
  FROM
    (SELECT unnest($1) AS node_id) x
    INNER JOIN nodes n ON (n.id = x.node_id)
  WHERE
    ($2 IS NULL AND n.version = (SELECT MAX(version) FROM nodes WHERE id = n.id)) OR
    ($2 IS NOT NULL AND n.version = (SELECT version FROM nodes WHERE id = n.id AND tstamp <= $2 ORDER BY tstamp DESC LIMIT 1));
$$ LANGUAGE sql;

--
-- OWL_GetChangesetData
--
CREATE FUNCTION OWL_GetChangesetData(int) RETURNS
  TABLE(
    type varchar(2),
    id bigint,
    version int,
    tstamp timestamp without time zone,
    tags hstore,
    geom geometry,
    nodes bigint[],
    prev_version int,
    prev_tags hstore,
    prev_geom geometry,
    prev_nodes bigint[],
    changeset_nodes bigint[]) AS $$

  WITH affected_nodes AS (
  SELECT
    'N'::text AS type,
    n.id,
    n.version,
    n.tstamp,
    n.tags,
    n.geom,
    NULL::bigint[] AS nodes,
    prev.version AS prev_version,
    prev.tags AS prev_tags,
    prev.geom AS prev_geom,
    NULL::bigint[] AS prev_nodes,
    NULL::bigint[] AS changeset_nodes
  FROM nodes n
  LEFT JOIN nodes prev ON (prev.id = n.id AND prev.version = n.version - 1)
  WHERE n.changeset_id = $1 AND (prev.version IS NOT NULL OR n.version = 1)
  )
SELECT DISTINCT ON (type, id, version) * FROM
(
  SELECT
    'W' AS type,
    w.id,
    w.version,
    w.tstamp,
    w.tags,
    OWL_MakeLine(w.nodes, NULL),
    w.nodes,
    prev.version AS prev_version,
    prev.tags AS prev_tags,
    OWL_MakeLine(prev.nodes, prev.tstamp) AS prev_geom,
    prev.nodes AS prev_nodes,
    (SELECT array_agg(id) FROM (SELECT id FROM affected_nodes an WHERE an.tags = an.prev_tags INTERSECT SELECT unnest(w.nodes)) x) AS changeset_nodes
  FROM ways w
  INNER JOIN ways prev ON (prev.id = w.id AND prev.version = w.version - 1)
  WHERE w.nodes && (SELECT array_agg(id) FROM affected_nodes an WHERE an.tags = an.prev_tags) AND
    w.tstamp < (SELECT MAX(tstamp) FROM affected_nodes) AND w.changeset_id != $1 AND
    OWL_MakeLine(w.nodes, NULL) IS NOT NULL AND (w.version = 1 OR OWL_MakeLine(prev.nodes, prev.tstamp) IS NOT NULL)

  UNION

  SELECT *
  FROM affected_nodes
  WHERE tags != prev_tags

  UNION

  SELECT *
  FROM affected_nodes
  WHERE tags != ''::hstore OR prev_tags != ''::hstore

  UNION

  SELECT
    'W' AS type,
    w.id,
    w.version,
    w.tstamp,
    w.tags,
    OWL_MakeLine(w.nodes, NULL),
    w.nodes,
    prev.version AS prev_version,
    prev.tags AS prev_tags,
    OWL_MakeLine(prev.nodes, prev.tstamp),
    prev.nodes AS prev_nodes,
    NULL::bigint[] AS changeset_nodes
  FROM ways w
  LEFT JOIN ways prev ON (prev.id = w.id AND prev.version = w.version - 1)
  WHERE w.changeset_id = $1 AND (prev.version IS NOT NULL OR w.version = 1) AND
    OWL_MakeLine(w.nodes, NULL) IS NOT NULL AND (w.version = 1 OR OWL_MakeLine(prev.nodes, prev.tstamp) IS NOT NULL)
) x
$$ LANGUAGE sql;

--
-- OWL_UpdateChangeset
--
CREATE FUNCTION OWL_UpdateChangeset(bigint) RETURNS void AS $$
DECLARE
  row record;
  idx int;
  result int[9];
  result_bbox geometry;
BEGIN
  result := ARRAY[0, 0, 0, 0, 0, 0, 0, 0, 0];
  FOR row IN
    SELECT
      CASE el_type WHEN 'N' THEN 0 WHEN 'W' THEN 1 WHEN 'R' THEN 2 END AS el_type_idx,
      CASE action WHEN 'CREATE' THEN 0 WHEN 'MODIFY' THEN 1 WHEN 'DELETE' THEN 2 END AS action_idx,
      COUNT(*) as cnt
    FROM changes
    WHERE changeset_id = $1
    GROUP BY el_type, action
  LOOP
    result[row.el_type_idx * 3 + row.action_idx + 1] := row.cnt;
  END LOOP;

  result_bbox := (SELECT ST_Envelope(ST_Collect(ST_Collect(current_geom, new_geom))) FROM changes WHERE changeset_id = $1);

  UPDATE changesets cs SET entity_changes = result, bbox = result_bbox
  WHERE cs.id = $1;
END;
$$ LANGUAGE plpgsql;

--
-- OWL_AggregateChangeset
--
CREATE FUNCTION OWL_AggregateChangeset(bigint, int, int) RETURNS void AS $$
DECLARE
  subtiles_per_tile bigint;

BEGIN
  subtiles_per_tile := POW(2, $2) / POW(2, $3);

  DELETE FROM tiles WHERE changeset_id = $1 AND zoom = $3;

  INSERT INTO tiles (changeset_id, tstamp, x, y, zoom, geom, prev_geom, changes)
  SELECT $1, MAX(tstamp), x/subtiles_per_tile, y/subtiles_per_tile, $3,
	ARRAY[]::geometry[], ARRAY[]::geometry[], ARRAY[]::bigint[]--ARRAY[((SELECT ST_Extent(unnest(geom))))::geometry]
  FROM tiles
  WHERE changeset_id = $1 AND zoom = $2
  GROUP BY x/subtiles_per_tile, y/subtiles_per_tile;
END;
$$ LANGUAGE plpgsql;
