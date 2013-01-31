CREATE OR REPLACE FUNCTION OWL_LatLonToTile(int, geometry) RETURNS table (x int, y int) AS $$
  SELECT
    floor((POW(2, $1) * ((ST_X($2) + 180) / 360)))::int AS tile_x,
    floor((1.0 - ln(tan(radians(ST_Y($2))) + 1.0 / cos(radians(ST_Y($2)))) / pi()) / 2.0 * POW(2, $1))::int AS tile_y;
$$ LANGUAGE SQL;

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
BEGIN
  RETURN OWL_MakeLine(
    (SELECT $1[MIN(idx($1, minimal_node)) - 2:MAX(idx($1, minimal_node)) + 2]
    FROM unnest($3) AS minimal_node), $2);
END
$$ LANGUAGE plpgsql IMMUTABLE;

--
-- OWL_RemoveTags
--
-- Removes "not interesting" tags from given hstore.
--
CREATE OR REPLACE FUNCTION OWL_RemoveTags(hstore) RETURNS hstore AS $$
  SELECT $1 - ARRAY['created_by', 'source']
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
-- OWL_JoinTileGeometriesByChange
--
-- Merges (collects/unions in the spatial sense) geometries belonging
-- to the same change.
--
-- $1 - an array of change ids
-- $2 - an array of geometries corresponding to changes from $1
--
-- The two arrays are of the same size. Returns an array of GeoJSON strings.
--
CREATE OR REPLACE FUNCTION OWL_JoinTileGeometriesByChange(bigint[], geometry(GEOMETRY, 4326)[]) RETURNS text[] AS $$
  WITH joined_arrays AS (
    SELECT change_id, geom, GeometryType(geom) AS geom_type
    FROM
      (SELECT row_number() OVER () AS seq, unnest AS change_id FROM unnest($1)) x
      INNER JOIN
      (SELECT row_number() OVER () AS seq, unnest AS geom FROM unnest($2)) y
      ON (x.seq = y.seq)
  )
  SELECT
    array_agg(CASE WHEN c.g IS NOT NULL AND NOT ST_IsEmpty(c.g) AND ST_NumGeometries(c.g) > 0 THEN ST_AsGeoJSON(ST_CollectionHomogenize(c.g)) ELSE NULL END order by c.change_id)
  FROM (
    SELECT ST_Collect(g) AS g, change_id
    FROM
      (SELECT NULL AS g, change_id
      FROM joined_arrays
      WHERE geom_type IS NULL
      GROUP BY change_id
        UNION
      SELECT ST_LineMerge(ST_Union(geom)) AS g, change_id
      FROM joined_arrays
      WHERE geom_type IS NOT NULL AND geom_type LIKE '%LINESTRING'
      GROUP BY change_id
        UNION
      SELECT ST_Union(geom) AS g, change_id
      FROM joined_arrays
      WHERE geom_type IS NOT NULL AND geom_type NOT LIKE '%LINESTRING'
      GROUP BY change_id) x
    GROUP BY change_id) c
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
  el_rev int,
  el_action action,
  tags hstore,
  prev_tags hstore,
  nodes bigint[],
  prev_nodes bigint[]
) AS $$

DECLARE
  min_tstamp timestamp without time zone;
  max_tstamp timestamp without time zone;
  row_count int;

BEGIN
  RAISE NOTICE '% -- Generating changes for changeset %', clock_timestamp(), $1;

  SELECT MAX(x.tstamp), MIN(x.tstamp) - INTERVAL '1 second'
  INTO max_tstamp, min_tstamp
  FROM (
    SELECT n.tstamp
    FROM nodes n
    WHERE n.changeset_id = $1
    UNION
    SELECT w.tstamp
    FROM way_revisions w
    WHERE w.changeset_id = $1
  ) x;

  RAISE NOTICE '% --   Prepared data (min = %, max = %)', clock_timestamp(), min_tstamp, max_tstamp;

  CREATE TEMPORARY TABLE _tmp_result ON COMMIT DROP AS
  SELECT
    $1,
    n.tstamp,
    n.changeset_id,
    'N'::element_type AS type,
    n.id,
    n.version,
    NULL::int,
    CASE
      WHEN n.version = 1 THEN 'CREATE'::action
      WHEN n.version > 1 AND n.visible THEN 'MODIFY'::action
      WHEN NOT n.visible THEN 'DELETE'::action
    END AS el_action,
    n.tags,
    prev.tags AS prev_tags,
    NULL::bigint[] AS nodes,
    NULL::bigint[] AS prev_nodes
  FROM nodes n
  LEFT JOIN nodes prev ON (prev.id = n.id AND prev.version = n.version - 1)
  WHERE n.changeset_id = $1 AND (prev.version IS NOT NULL OR n.version = 1) AND
    OWL_RemoveTags(n.tags) != ''::hstore OR OWL_RemoveTags(prev.tags) != ''::hstore;

  GET DIAGNOSTICS row_count = ROW_COUNT;
  RAISE NOTICE '% --   Nodes done (%)', clock_timestamp(), row_count;

  -- Created ways

  INSERT INTO _tmp_result
  SELECT
    $1,
    w.tstamp,
    w.changeset_id,
    'W'::element_type AS type,
    w.id,
    w.version,
    rev.revision,
    'CREATE',
    w.tags,
    NULL,
    w.nodes,
    NULL
  FROM way_revisions rev
  INNER JOIN ways w ON (w.id = rev.way_id AND w.version = rev.way_version)
  WHERE rev.changeset_id = $1 AND rev.revision = 1;

  GET DIAGNOSTICS row_count = ROW_COUNT;
  RAISE NOTICE '% --   Created ways done (%)', clock_timestamp(), row_count;

  -- Modified ways

  INSERT INTO _tmp_result
  SELECT
    $1,
    w.tstamp,
    w.changeset_id,
    'W'::element_type AS type,
    w.id,
    w.version,
    rev.revision,
    'MODIFY',
    w.tags,
    prev_way.tags,
    w.nodes,
    prev_way.nodes
  FROM way_revisions rev
  INNER JOIN way_revisions prev_rev ON (prev_rev.way_id = rev.way_id AND prev_rev.revision = rev.revision - 1)
  INNER JOIN ways w ON (w.id = rev.way_id AND w.version = rev.way_version)
  INNER JOIN ways prev_way ON (prev_way.id = prev_rev.way_id AND prev_way.version = prev_rev.way_version)
  WHERE rev.changeset_id = $1 AND rev.visible;

  GET DIAGNOSTICS row_count = ROW_COUNT;
  RAISE NOTICE '% --   Modified ways done (%)', clock_timestamp(), row_count;

  -- Deleted ways

  INSERT INTO _tmp_result
  SELECT
    $1,
    w.tstamp,
    w.changeset_id,
    'W'::element_type AS type,
    w.id,
    w.version,
    rev.revision,
    'DELETE',
    w.tags,
    prev_way.tags,
    w.nodes,
    prev_way.nodes
  FROM way_revisions rev
  INNER JOIN way_revisions prev_rev ON (prev_rev.way_id = rev.way_id AND prev_rev.revision = rev.revision - 1)
  INNER JOIN ways w ON (w.id = rev.way_id AND w.version = rev.way_version)
  INNER JOIN ways prev_way ON (prev_way.id = prev_rev.way_id AND prev_way.version = prev_rev.way_version)
  WHERE rev.changeset_id = $1 AND NOT rev.visible;

  GET DIAGNOSTICS row_count = ROW_COUNT;
  RAISE NOTICE '% --   Deleted ways done (%)', clock_timestamp(), row_count;

  RETURN QUERY SELECT * FROM _tmp_result;
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
-- OWL_AggregateChangeset
--
CREATE OR REPLACE FUNCTION OWL_AggregateChangeset(bigint, int, int) RETURNS void AS $$
DECLARE
  subtiles_per_tile bigint;

BEGIN
  subtiles_per_tile := POW(2, $2) / POW(2, $3);

  DELETE FROM changeset_tiles WHERE changeset_id = $1 AND zoom = $3;

  INSERT INTO changeset_tiles (changeset_id, tstamp, x, y, zoom, geom, prev_geom, changes)
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
  FROM changeset_tiles
  WHERE changeset_id = $1 AND zoom = $2
  GROUP BY x/subtiles_per_tile, y/subtiles_per_tile;
END;
$$ LANGUAGE plpgsql;

--
-- OWL_CreateWayRevisions
--
CREATE OR REPLACE FUNCTION OWL_CreateWayRevisions(bigint) RETURNS void AS $$
DECLARE
  first_version boolean;
  current_revision int;
  rev record;
  prev_way record;
  way record;

BEGIN
  current_revision := 0;
  first_version := true;
  FOR way IN SELECT * FROM ways WHERE id = $1 ORDER BY version LOOP
    RAISE NOTICE 'Way % version %', way.id, way.version;

    IF NOT first_version THEN
      FOR rev IN
          SELECT MAX(n.tstamp) AS tstamp, n.changeset_id, n.user_id
          FROM nodes n
          INNER JOIN nodes n2 ON (n.id = n2.id AND n.version = n2.version + 1)
          WHERE n.id IN (SELECT unnest(prev_way.nodes)) AND n.tstamp > prev_way.tstamp AND n.tstamp < way.tstamp
            AND NOT n.geom = n2.geom
          GROUP BY n.changeset_id, n.user_id
          ORDER BY tstamp
      LOOP
        current_revision := current_revision + 1;
        INSERT INTO way_revisions (way_id, way_version, revision, user_id, tstamp, changeset_id, visible)
        VALUES ($1, way.version - 1, current_revision, rev.user_id, rev.tstamp, rev.changeset_id, prev_way.visible);
      END LOOP;
    END IF;

    current_revision := current_revision + 1;

    INSERT INTO way_revisions (way_id, way_version, revision, user_id, tstamp, changeset_id, visible)
    VALUES ($1, way.version, current_revision, way.user_id, way.tstamp, way.changeset_id, way.visible);

    prev_way := way;
    first_version := false;
  END LOOP;

  FOR rev IN
      SELECT MAX(n.tstamp) AS tstamp, n.changeset_id, n.user_id
      FROM nodes n
      INNER JOIN nodes n2 ON (n.id = n2.id AND n.version = n2.version + 1)
      WHERE n.id IN (SELECT unnest(prev_way.nodes)) AND n.tstamp > prev_way.tstamp AND n.tstamp <= NOW()
        AND NOT n.geom = n2.geom
      GROUP BY n.changeset_id, n.user_id
      ORDER BY tstamp
  LOOP
    current_revision := current_revision + 1;
    INSERT INTO way_revisions (way_id, way_version, revision, user_id, tstamp, changeset_id, visible)
    VALUES ($1, prev_way.version, current_revision, rev.user_id, rev.tstamp, rev.changeset_id, prev_way.visible);
  END LOOP;
END;
$$ LANGUAGE plpgsql;
