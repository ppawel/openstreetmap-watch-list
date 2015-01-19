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

CREATE OR REPLACE FUNCTION OWL_IsPolygon(hstore) RETURNS boolean AS
$$
  SELECT $1 IS NOT NULL AND
    ($1 ? 'area' OR $1 ? 'landuse' OR $1 ? 'leisure' OR $1 ? 'amenity' OR $1 ? 'building')
$$ LANGUAGE sql IMMUTABLE;

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
  way_geom := (SELECT ST_MakeLine(q.geom ORDER BY x.seq)
    FROM (SELECT row_number() OVER () AS seq, n AS node_id FROM unnest($1) n) x
    INNER JOIN (
      SELECT DISTINCT ON (id) id, geom
      FROM nodes n
      WHERE n.id IN (SELECT unnest($1))
      AND tstamp <= $2 AND visible
      ORDER BY id, version DESC, tstamp DESC) q ON (q.id = x.node_id));

  -- Now check if the linestring has exactly the right number of points.
  IF ST_NumPoints(way_geom) != array_length($1, 1) THEN
    RETURN NULL;
  END IF;

  RETURN ST_MakeValid(way_geom);
END;
$$ LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION OWL_MakeLineFromTmpNodes(bigint[]) RETURNS geometry(GEOMETRY, 4326) AS $$
DECLARE
  way_geom geometry(GEOMETRY, 4326);

BEGIN
  way_geom := (SELECT ST_MakeLine(geom ORDER BY seq) FROM _tmp_current_nodes);

  -- Now check if the linestring has exactly the right number of points.
  IF ST_NumPoints(way_geom) != array_length($1, 1) THEN
    --raise notice '--------------- %, %', $1, (select array_agg(id) from _tmp_nodes);
    RETURN NULL;
  END IF;

  RETURN ST_MakeValid(way_geom);
END;
$$ LANGUAGE plpgsql VOLATILE;

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
BEGIN
  RETURN OWL_MakeLine(
    (SELECT $1[MIN(idx($1, minimal_node)) - 2:MAX(idx($1, minimal_node)) + 2]
    FROM unnest($3) AS minimal_node), $2);
END
$$ LANGUAGE plpgsql IMMUTABLE;

--
-- OWL_InterestingTags
--
CREATE OR REPLACE FUNCTION OWL_InterestingTags(hstore) RETURNS boolean AS $$
  SELECT $1 IS NOT NULL AND $1 - ARRAY['created_by', 'source'] != ''
$$ LANGUAGE sql IMMUTABLE;

--
-- OWL_Equals
--
-- Determines if two geometries are the same or not in OWL sense. That is,
-- very small changes in node geometry are ignored as they are not really
-- useful to consider as data changes.
--
CREATE OR REPLACE FUNCTION OWL_Equals(geometry(GEOMETRY, 4326), geometry(GEOMETRY, 4326)) RETURNS boolean AS $$
BEGIN
  IF $1 IS NULL OR $2 IS NULL THEN
    RETURN NULL;
  END IF;

  IF GeometryType($1) = 'POINT' AND GeometryType($2) = 'POINT' THEN
    RETURN $1 = $2;
  END IF;

  IF ST_OrderingEquals($1, $2) THEN
    RETURN true;
  END IF;

  RETURN OWL_Equals_Simple($1, $2);
END
$$ LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION OWL_Equals_Buffer(geometry(GEOMETRY, 4326), geometry(GEOMETRY, 4326)) RETURNS boolean AS $$
DECLARE
  buf1 geometry(GEOMETRY, 4326);
  buf2 geometry(GEOMETRY, 4326);
  union_area float;
  intersection_area float;

BEGIN
  buf1 := ST_Buffer($1, 0.0002);
  buf2 := ST_Buffer($2, 0.0002);
  union_area := ST_Area(ST_Union(buf1, buf2));
  intersection_area := ST_Area(ST_Intersection(buf1, buf2));
  IF intersection_area = 0.0 THEN RETURN false; END IF;
  RETURN ABS(1.0 - union_area / intersection_area) < 0.0002;
END
$$ LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION OWL_Equals_Snap(geometry(GEOMETRY, 4326), geometry(GEOMETRY, 4326)) RETURNS boolean AS $$
  SELECT ST_Equals(ST_SnapToGrid(st_Segmentize($1, 0.00002), 0.0002), ST_SnapToGrid(st_Segmentize($2, 0.00002), 0.0002));
$$ LANGUAGE sql IMMUTABLE;

CREATE OR REPLACE FUNCTION OWL_Equals_Simple(geometry(GEOMETRY, 4326), geometry(GEOMETRY, 4326)) RETURNS boolean AS $$
  SELECT ABS(ST_Area($1::box2d) - ST_Area($2::box2d)) < 0.0002 AND
    ABS(ST_Length($1) - ST_Length($2)) < 0.0002;
$$ LANGUAGE sql IMMUTABLE;

--
-- OWL_GenerateChanges
--
CREATE OR REPLACE FUNCTION OWL_GenerateChanges(bigint) RETURNS VOID AS $$
DECLARE
  min_tstamp timestamp without time zone;
  max_tstamp timestamp without time zone;
  moved_nodes_ids bigint[];
  row_count int;

BEGIN
  RAISE NOTICE '% -- Generating changes for changeset %', clock_timestamp(), $1;

  CREATE TEMPORARY TABLE _tmp_result (
    tstamp timestamp without time zone,
    el_type element_type,
    action action,
    el_id bigint,
    version int,
    tags hstore,
    prev_tags hstore,
    geom geometry(GEOMETRY, 4326),
    prev_geom geometry(GEOMETRY, 4326),
    nodes bigint[],
    prev_nodes bigint[]
  ) ON COMMIT DROP;

  INSERT INTO _tmp_result
  SELECT
    n.tstamp,
    'N'::element_type,
    CASE
      WHEN n.version = 1 THEN 'CREATE'::action
      WHEN n.version > 1 AND n.visible THEN 'MODIFY'::action
      WHEN NOT n.visible THEN 'DELETE'::action
    END::action,
    n.id,
    n.version,
    n.tags,
    prev.tags,
    n.geom,
    prev.geom,
    NULL::bigint[],
    NULL::bigint[]
  FROM nodes n
  LEFT JOIN nodes prev ON (prev.id = n.id AND prev.version = n.version - 1)
  WHERE n.changeset_id = $1 AND (prev.version IS NOT NULL OR n.version = 1);

  GET DIAGNOSTICS row_count = ROW_COUNT;
  RAISE NOTICE '% --   Changeset nodes selected (%)', clock_timestamp(), row_count;

  INSERT INTO _tmp_result
  SELECT
    w.tstamp,
    'W'::element_type,
    CASE
      WHEN w.version = 1 THEN 'CREATE'::action
      WHEN w.version > 1 AND w.visible THEN 'MODIFY'::action
      WHEN NOT w.visible THEN 'DELETE'::action
    END,
    w.id,
    w.version,
    w.tags,
    prev.tags,
    NULL,
    NULL,
    w.nodes,
    prev.nodes
  FROM ways w
  LEFT JOIN ways prev ON (prev.id = w.id AND prev.version = w.version - 1)
  WHERE w.changeset_id = $1 AND (prev.version IS NOT NULL OR w.version = 1);

  GET DIAGNOSTICS row_count = ROW_COUNT;
  RAISE NOTICE '% --   Changeset ways selected (%)', clock_timestamp(), row_count;

  SELECT MAX(tstamp), MIN(tstamp)
  INTO max_tstamp, min_tstamp
  FROM _tmp_result;

  moved_nodes_ids := (SELECT array_agg(el_id) FROM _tmp_result
    WHERE el_type = 'N' AND version > 1 AND NOT geom = prev_geom AND action != 'DELETE');

  RAISE NOTICE '% --   Prepared data (min = %, max = %, moved nodes = %)', clock_timestamp(),
    min_tstamp, max_tstamp, array_length(moved_nodes_ids, 1);

  -- Affected ways

  INSERT INTO _tmp_result
  SELECT
    w.tstamp,
    'W'::element_type,
    'AFFECT'::action,
    w.id,
    version,
    w.tags,
    w.tags,
    NULL,
    NULL,
    w.nodes,
    w.nodes
      --OWL_MakeMinimalLine(w.nodes, max_tstamp, array_intersect(w.nodes, moved_nodes_ids)) AS geom,
      --OWL_MakeMinimalLine(w.nodes, min_tstamp, array_intersect(w.nodes, moved_nodes_ids)) AS prev_geom
      --OWL_MakeLine(w.nodes, max_tstamp) AS geom,
      --OWL_MakeLine(w.nodes, min_tstamp) AS prev_geom
  FROM ways w
  WHERE w.nodes && moved_nodes_ids AND
    w.version = (SELECT version FROM ways WHERE id = w.id AND tstamp <= max_tstamp ORDER BY version DESC LIMIT 1);

  GET DIAGNOSTICS row_count = ROW_COUNT;
  RAISE NOTICE '% --   Affected ways done (%)', clock_timestamp(), row_count;

  DELETE FROM _tmp_result
  WHERE el_type = 'N' AND el_id IN (SELECT unnest(nodes) FROM _tmp_result UNION SELECT unnest(prev_nodes) FROM _tmp_result)
    AND NOT OWL_InterestingTags(tags) AND NOT OWL_InterestingTags(prev_tags);

  GET DIAGNOSTICS row_count = ROW_COUNT;
  RAISE NOTICE '% --   Removed not interesting nodes (%)', clock_timestamp(), row_count;

  UPDATE _tmp_result w
  SET action = 'CREATE', prev_geom = NULL
  WHERE el_type = 'W' AND EXISTS
    (SELECT 1 FROM _tmp_result w2 WHERE w2.el_type = 'W' AND w2.el_id = w.el_id AND w2.action = 'CREATE');

  DELETE FROM _tmp_result w
  WHERE el_type = 'W' AND version < (SELECT MAX(w2.version) FROM _tmp_result w2 WHERE w2.el_type = 'W' AND w2.el_id = w.el_id);

  GET DIAGNOSTICS row_count = ROW_COUNT;
  RAISE NOTICE '% --   Removed old changes (%)', clock_timestamp(), row_count;

  UPDATE _tmp_result
  SET
    geom =
      CASE
        WHEN action = 'DELETE' THEN NULL
        ELSE OWL_MakeLine(nodes, max_tstamp)
      END,
    prev_geom =
      CASE
        WHEN action = 'CREATE' THEN NULL
        ELSE OWL_MakeLine(prev_nodes, min_tstamp - interval '1 second')
      END
  WHERE el_type = 'W';

  GET DIAGNOSTICS row_count = ROW_COUNT;
  RAISE NOTICE '% --   Updated way geoms (%)', clock_timestamp(), row_count;

  DELETE FROM _tmp_result
  WHERE el_type = 'W' AND geom IS NOT NULL AND prev_geom IS NOT NULL
    AND OWL_Equals(geom, prev_geom) AND tags = prev_tags AND nodes = prev_nodes;

  GET DIAGNOSTICS row_count = ROW_COUNT;
  RAISE NOTICE '% --   Removed not interesting ways (%)', clock_timestamp(), row_count;

  RAISE NOTICE '% -- Returning % change(s)', clock_timestamp(), (SELECT COUNT(*) FROM _tmp_result);

  WITH _tmp_changes AS (
    SELECT *, ROW_NUMBER() OVER(PARTITION BY el_id ORDER BY version DESC, tstamp DESC) AS rownum
    FROM _tmp_result
  )
  INSERT INTO changes (
    tstamp,
    el_type,
    action,
    el_id,
    version,
    changeset_id,
    tags,
    prev_tags,
    geom,
    prev_geom)
  SELECT
    tstamp,
    el_type,
    action,
    el_id,
    version,
    $1,
    tags,
    prev_tags,
    geom,
    NULL--prev_geom
  FROM
    _tmp_changes
  WHERE rownum = 1;
END
$$ LANGUAGE plpgsql;

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

  DELETE FROM changeset_tiles WHERE changeset_id = $1 AND zoom = $3;

  INSERT INTO changeset_tiles (changeset_id, change_id, tstamp, x, y, zoom, geom, prev_geom)
  SELECT
    $1,
    change_id,
    MAX(tstamp),
    x/subtiles_per_tile,
    y/subtiles_per_tile,
    $3,
    ST_Union(geom),
    ST_Union(prev_geom)
  FROM changeset_tiles
  WHERE changeset_id = $1 AND zoom = $2
  GROUP BY x/subtiles_per_tile, y/subtiles_per_tile, change_id;
END;
$$ LANGUAGE plpgsql;
