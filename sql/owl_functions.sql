--
-- Returns index of an element in given array.
--
-- Source: http://wiki.postgresql.org/wiki/Array_Index
--
CREATE OR REPLACE FUNCTION idx(anyarray, anyelement)
  RETURNS int AS
$$
  SELECT i FROM (
     SELECT generate_series(array_lower($1,1),array_upper($1,1))
  ) g(i)
  WHERE $1[i] = $2
  LIMIT 1;
$$ LANGUAGE sql IMMUTABLE;

--
-- Returns the intersection of two arrays.
--
CREATE OR REPLACE FUNCTION array_intersect(anyarray, anyarray)
  RETURNS anyarray
  language sql
as $FUNCTION$
    SELECT ARRAY(
        SELECT UNNEST($1)
        INTERSECT
        SELECT UNNEST($2)
    );
$FUNCTION$;

--
-- OWL_MakeLine
--
-- Creates a linestring from given list of node ids. If timestamp is given,
-- the node versions used are filtered by this timestamp (are no newer than).
-- This is useful for creating way geometry for historic versions.
--
-- Note that it returns NULL when it cannot recreate the geometry, e.g. when
-- there is not enough historical node versions in the database.
--
CREATE OR REPLACE FUNCTION OWL_MakeLine(bigint[], timestamp without time zone) RETURNS geometry(GEOMETRY, 4326) AS $$
DECLARE
  way_geom geometry(GEOMETRY, 4326);

BEGIN
  way_geom := (SELECT ST_MakeLine(geom)
  FROM
    (SELECT unnest($1) AS node_id) x
    INNER JOIN nodes n ON (n.id = x.node_id)
  WHERE
    n.version = (SELECT version FROM nodes WHERE id = n.id AND tstamp <= $2 ORDER BY tstamp DESC LIMIT 1));

  -- Now check if the linestring has exactly the right number of points.
  IF ST_NumPoints(way_geom) != array_length($1, 1) THEN
    way_geom := NULL;
  END IF;

  -- Invalid way geometry - convert to a single point.
  IF ST_NumPoints(way_geom) = 1 THEN
    way_geom := ST_PointN(way_geom, 1);
  END IF;

  RETURN way_geom;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

--
-- OWL_MakeMinimalLine
--
-- Creates a line from given nodes just as OWL_MakeLine does but also
-- considers additional array of "minimal" nodes. If it's possible to
-- build a shorter line using this subset of all nodes then do it.
--
-- $1 - all nodes
-- $2 - tstamp to use for constructing geometry
-- $3 - "minimal" nodes (needs to be a subset of $1)
--
CREATE OR REPLACE FUNCTION OWL_MakeMinimalLine(bigint[], timestamp without time zone, bigint[]) RETURNS geometry(GEOMETRY, 4326) AS $$
  SELECT OWL_MakeLine(
    (SELECT $1[MIN(idx($1, minimal_node)) - 2:MAX(idx($1, minimal_node)) + 2]
    FROM unnest($3) AS minimal_node), $2)
$$ LANGUAGE sql IMMUTABLE;

CREATE OR REPLACE FUNCTION OWL_JoinTileGeometriesByChange(bigint[], geometry(GEOMETRY, 4326)[]) RETURNS text[] AS $$
 SELECT array_agg(CASE WHEN c.g IS NOT NULL AND NOT ST_IsEmpty(c.g) AND ST_NumGeometries(c.g) > 0 THEN ST_AsGeoJSON(c.g) ELSE NULL END) FROM
 (
 SELECT ST_Union(y.geom) AS g, x.change_id
 FROM
   (SELECT row_number() OVER () AS seq, unnest AS change_id FROM unnest($1)) x
   INNER JOIN
   (SELECT row_number() OVER () AS seq, unnest AS geom FROM unnest($2)) y
   ON (x.seq = y.seq)
 GROUP BY x.change_id
 ORDER BY x.change_id) c
$$ LANGUAGE sql IMMUTABLE;

--
-- OWL_GenerateChanges
--
CREATE OR REPLACE FUNCTION OWL_GenerateChanges(bigint) RETURNS TABLE (
  changeset_id bigint,
  tstamp timestamp without time zone,
  el_changeset_id bigint,
  el_type element_type,
  el_id bigint,
  el_version int,
  el_action action,
  geom_changed boolean,
  tags_changed boolean,
  nodes_changed boolean,
  members_changed boolean,
  geom geometry(GEOMETRY, 4326),
  prev_geom geometry(GEOMETRY, 4326),
  tags hstore,
  prev_tags hstore,
  nodes bigint[],
  prev_nodes bigint[]
) AS $$

  WITH changeset_nodes AS (
    SELECT
        $1,
        n.tstamp,
        n.changeset_id,
        'N'::element_type AS type,
        n.id,
        n.version,
        CASE
          WHEN n.version = 1 THEN 'CREATE'::action
          WHEN n.version > 0 AND n.visible THEN 'MODIFY'::action
          WHEN NOT n.visible THEN 'DELETE'::action
        END AS el_type,
        NOT n.geom = prev.geom AS geom_changed,
        n.tags != prev.tags AS tags_changed,
        NULL::boolean AS nodes_changed,
        NULL::boolean AS members_changed,
        CASE WHEN NOT n.visible THEN NULL ELSE n.geom END AS geom,
        CASE WHEN NOT n.visible OR NOT n.geom = prev.geom THEN prev.geom ELSE NULL END AS prev_geom,
        n.tags,
        prev.tags AS prev_tags,
        NULL::bigint[] AS nodes,
        NULL::bigint[] AS prev_nodes
    FROM nodes n
    LEFT JOIN nodes prev ON (prev.id = n.id AND prev.version = n.version - 1)
    WHERE n.changeset_id = $1 AND (prev.version IS NOT NULL OR n.version = 1)
  ),
  moved_nodes AS (
    SELECT * FROM changeset_nodes WHERE version > 1 AND geom_changed
  ),
  tstamps AS (
    SELECT MAX(x.tstamp) AS max, MIN(x.tstamp) - INTERVAL '1 second' AS min
    FROM (
      SELECT tstamp
      FROM nodes
      WHERE changeset_id = $1
      UNION
      SELECT tstamp
      FROM ways
      WHERE changeset_id = $1
    ) x
  )

  SELECT
    $1,
    w.tstamp,
    w.changeset_id,
    'W'::element_type AS type,
    w.id,
    w.version,
    CASE
      WHEN w.version = 1 THEN 'CREATE'::action
      WHEN w.version > 0 AND w.visible THEN 'MODIFY'::action
      WHEN NOT w.visible THEN 'DELETE'::action
    END AS el_action,
    NOT ST_OrderingEquals(geom, prev_geom),
    w.tags != prev_tags,
    w.nodes != prev_nodes,
    NULL,
    geom,
    CASE WHEN w.visible AND ST_OrderingEquals(geom, prev_geom) THEN NULL ELSE prev_geom END,
    w.tags,
    prev_tags,
    w.nodes,
    CASE WHEN w.nodes = prev_nodes THEN NULL ELSE prev_nodes END
  FROM
    (SELECT w.*, prev.tags AS prev_tags, prev.nodes AS prev_nodes,
      OWL_MakeLine(w.nodes, (SELECT max FROM tstamps)) AS geom,
      OWL_MakeLine(prev.nodes, (SELECT min FROM tstamps)) AS prev_geom
    FROM ways w
    LEFT JOIN ways prev ON (prev.id = w.id AND prev.version = w.version - 1)
    WHERE w.changeset_id = $1 AND
      (prev.version IS NOT NULL OR w.version = 1) AND
      (OWL_MakeLine(w.nodes, (SELECT max FROM tstamps)) IS NOT NULL OR NOT w.visible) AND
      (w.version = 1 OR OWL_MakeLine(prev.nodes, (SELECT min FROM tstamps)) IS NOT NULL)
    ) w
  WHERE NOT ST_OrderingEquals(geom, prev_geom) OR w.tags != prev_tags OR w.version = 1

  UNION

  SELECT *
  FROM changeset_nodes
  WHERE tags != prev_tags

  UNION

  SELECT *
  FROM changeset_nodes
  WHERE (tags - ARRAY['created_by', 'source']) != ''::hstore OR (prev_tags - ARRAY['created_by', 'source']) != ''::hstore

  UNION

  SELECT
    $1,
    tstamp,
    changeset_id,
    'W'::element_type AS type,
    id,
    version,
    'AFFECT'::action,
    true,
    false,
    false,
    NULL,
    geom,
    prev_geom,
    tags,
    NULL,
    nodes,
    NULL
  FROM (
    SELECT
      *,
      OWL_MakeMinimalLine(w.nodes, (SELECT max FROM tstamps), array_intersect(w.nodes, (SELECT array_agg(id) FROM moved_nodes))) AS geom,
      OWL_MakeMinimalLine(w.nodes, (SELECT min FROM tstamps), array_intersect(w.nodes, (SELECT array_agg(id) FROM moved_nodes))) AS prev_geom
    FROM ways w
    WHERE w.nodes && (SELECT array_agg(id) FROM changeset_nodes an WHERE an.version > 1 AND an.geom_changed) AND
      w.version = (SELECT version FROM ways WHERE id = w.id AND
        tstamp <= (SELECT max FROM tstamps) ORDER BY version DESC LIMIT 1) AND
      w.changeset_id != $1 AND
      OWL_MakeLine(w.nodes, (SELECT max FROM tstamps)) IS NOT NULL AND
      (w.version = 1 OR OWL_MakeLine(w.nodes, (SELECT min FROM tstamps)) IS NOT NULL)) w;

$$ LANGUAGE sql IMMUTABLE;

--
-- OWL_UpdateChangeset
--
CREATE OR REPLACE FUNCTION OWL_UpdateChangeset(bigint) RETURNS void AS $$
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
CREATE OR REPLACE FUNCTION OWL_AggregateChangeset(bigint, int, int) RETURNS void AS $$
DECLARE
  subtiles_per_tile bigint;

BEGIN
  subtiles_per_tile := POW(2, $2) / POW(2, $3);

  DELETE FROM tiles WHERE changeset_id = $1 AND zoom = $3;

  INSERT INTO tiles (changeset_id, tstamp, x, y, zoom, geom, prev_geom, changes)
  SELECT
  $1,
  MAX(tstamp),
  x/subtiles_per_tile,
  y/subtiles_per_tile,
  $3,
  CASE
    WHEN $3 >= 14 THEN array_accum(geom)
    ELSE array_accum((SELECT array_agg(ST_Envelope(unnest)) FROM unnest(geom)))
  END,
  CASE
    WHEN $3 >= 14 THEN array_accum(prev_geom)
    ELSE array_accum((SELECT array_agg(ST_Envelope(unnest)) FROM unnest(prev_geom)))
  END,
  array_accum(changes)
  FROM tiles
  WHERE changeset_id = $1 AND zoom = $2
  GROUP BY x/subtiles_per_tile, y/subtiles_per_tile;
END;
$$ LANGUAGE plpgsql;
