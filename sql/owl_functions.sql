DROP FUNCTION IF EXISTS OWL_MakeLine(bigint[], timestamp without time zone);
DROP FUNCTION IF EXISTS OWL_JoinTileGeometriesByChange(bigint[], geometry(GEOMETRY, 4326)[]);
DROP FUNCTION IF EXISTS OWL_GenerateChanges(bigint);
DROP FUNCTION IF EXISTS OWL_UpdateChangeset(bigint);
DROP FUNCTION IF EXISTS OWL_AggregateChangeset(bigint, int, int);

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
CREATE FUNCTION OWL_MakeLine(bigint[], timestamp without time zone) RETURNS geometry(GEOMETRY, 4326) AS $$
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

CREATE FUNCTION OWL_JoinTileGeometriesByChange(bigint[], geometry(GEOMETRY, 4326)[]) RETURNS text[] AS $$
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
CREATE FUNCTION OWL_GenerateChanges(bigint) RETURNS TABLE (
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

  WITH affected_nodes AS (
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
        (NOT n.geom = prev.geom) OR n.version = 1 AS geom_changed,
        n.tags != prev.tags OR n.version = 1 AS tags_changed,
        NULL::boolean AS nodes_changed,
        NULL::boolean AS members_changed,
        n.geom AS geom,
        prev.geom AS prev_geom,
        n.tags,
        prev.tags AS prev_tags,
        NULL::bigint[] AS nodes,
        NULL::bigint[] AS prev_nodes
    FROM nodes n
    LEFT JOIN nodes prev ON (prev.id = n.id AND prev.version = n.version - 1)
    WHERE n.changeset_id = $1 AND (prev.version IS NOT NULL OR n.version = 1)
  ), tstamps AS (
    SELECT MAX(x.tstamp) AS max, MIN(x.tstamp) AS min
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
      END AS el_type,
      (NOT OWL_MakeLine(w.nodes, (SELECT max FROM tstamps)) = OWL_MakeLine(prev.nodes, (SELECT min FROM tstamps))) OR w.version = 1,
      w.tags != prev.tags OR w.version = 1,
      w.nodes != prev.nodes OR w.version = 1,
      NULL,
      OWL_MakeLine(w.nodes, (SELECT max FROM tstamps)),
      OWL_MakeLine(prev.nodes, (SELECT min FROM tstamps)),
      w.tags,
      prev.tags,
      w.nodes,
      prev.nodes
    FROM ways w
    LEFT JOIN ways prev ON (prev.id = w.id AND prev.version = w.version - 1)
    WHERE w.changeset_id = $1 AND (prev.version IS NOT NULL OR w.version = 1) AND
      OWL_MakeLine(w.nodes, (SELECT max FROM tstamps)) IS NOT NULL AND
      (w.version = 1 OR OWL_MakeLine(prev.nodes, (SELECT min FROM tstamps)) IS NOT NULL)

  UNION

  SELECT *
  FROM affected_nodes
  WHERE tags != prev_tags

  UNION

  SELECT *
  FROM affected_nodes
  WHERE (tags - ARRAY['created_by', 'source']) != ''::hstore OR (prev_tags - ARRAY['created_by', 'source']) != ''::hstore

  UNION

  SELECT
      $1,
      w.tstamp,
      w.changeset_id,
      'W'::element_type AS type,
      w.id,
      w.version,
      'MODIFY'::action,
      (NOT OWL_MakeLine(w.nodes, (SELECT max FROM tstamps)) = OWL_MakeLine(prev.nodes, (SELECT min FROM tstamps))) OR w.version = 1,
      w.tags != prev.tags OR w.version = 1,
      w.nodes != prev.nodes OR w.version = 1,
      NULL,
      OWL_MakeLine(w.nodes, (SELECT max FROM tstamps)),
      OWL_MakeLine(prev.nodes, (SELECT min FROM tstamps)),
      w.tags,
      prev.tags,
      w.nodes,
      prev.nodes
  FROM ways w
  LEFT JOIN ways prev ON (prev.id = w.id AND prev.version = w.version - 1)
  WHERE w.nodes && (SELECT array_agg(id) FROM affected_nodes an WHERE an.version > 1) AND
    w.version = (SELECT version FROM ways WHERE id = w.id AND
      tstamp <= (SELECT max FROM tstamps) ORDER BY version DESC LIMIT 1) AND
    w.changeset_id != $1 AND
    OWL_MakeLine(w.nodes, (SELECT max FROM tstamps)) IS NOT NULL AND
    (w.version = 1 OR OWL_MakeLine(prev.nodes, (SELECT min FROM tstamps)) IS NOT NULL);
$$ LANGUAGE sql IMMUTABLE;

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
