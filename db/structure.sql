--
-- PostgreSQL database dump
--

SET statement_timeout = 0;
SET lock_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


--
-- Name: hstore; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS hstore WITH SCHEMA public;


--
-- Name: EXTENSION hstore; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION hstore IS 'data type for storing sets of (key, value) pairs';


--
-- Name: postgis; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;


--
-- Name: EXTENSION postgis; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION postgis IS 'PostGIS geometry, geography, and raster spatial types and functions';


SET search_path = public, pg_catalog;

--
-- Name: action; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE action AS ENUM (
    'CREATE',
    'MODIFY',
    'DELETE',
    'AFFECT'
);


--
-- Name: element_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE element_type AS ENUM (
    'N',
    'W',
    'R'
);


--
-- Name: change; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE change AS (
	id integer,
	tstamp timestamp without time zone,
	el_type element_type,
	action action,
	el_id bigint,
	version integer,
	tags hstore,
	prev_tags hstore,
	geom geometry(Geometry,4326),
	prev_geom geometry(Geometry,4326)
);


--
-- Name: array_intersect(anyarray, anyarray); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION array_intersect(anyarray, anyarray) RETURNS anyarray
    LANGUAGE sql
    AS $_$
    SELECT ARRAY(
        SELECT UNNEST($1)
        INTERSECT
        SELECT UNNEST($2)
    );
$_$;


--
-- Name: idx(anyarray, anyelement); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION idx(anyarray, anyelement) RETURNS integer
    LANGUAGE sql IMMUTABLE
    AS $_$
  SELECT i FROM (
     SELECT generate_series(array_lower($1,1),array_upper($1,1))
  ) g(i)
  WHERE $1[i] = $2
  LIMIT 1;
$_$;


--
-- Name: owl_aggregatechangeset(bigint, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION owl_aggregatechangeset(bigint, integer, integer) RETURNS void
    LANGUAGE plpgsql
    AS $_$
DECLARE
  subtiles_per_tile bigint;

BEGIN
  subtiles_per_tile := POW(2, $2) / POW(2, $3);

  DELETE FROM changeset_tiles WHERE changeset_id = $1 AND zoom = $3;

  INSERT INTO changeset_tiles (changeset_id, tstamp, x, y, zoom, geom, prev_geom, changes)
  SELECT
  $1,
  MAX(tstamp),
  x/subtiles_per_tile * subtiles_per_tile,
  y/subtiles_per_tile * subtiles_per_tile,
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
$_$;


--
-- Name: owl_equals(geometry, geometry); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION owl_equals(geometry, geometry) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    AS $_$
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
$_$;


--
-- Name: owl_equals_buffer(geometry, geometry); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION owl_equals_buffer(geometry, geometry) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    AS $_$
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
$_$;


--
-- Name: owl_equals_simple(geometry, geometry); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION owl_equals_simple(geometry, geometry) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $_$
  SELECT ABS(ST_Area($1::box2d) - ST_Area($2::box2d)) < 0.0002 AND
    ABS(ST_Length($1) - ST_Length($2)) < 0.0002;
$_$;


--
-- Name: owl_equals_snap(geometry, geometry); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION owl_equals_snap(geometry, geometry) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $_$
  SELECT ST_Equals(ST_SnapToGrid(st_Segmentize($1, 0.00002), 0.0002), ST_SnapToGrid(st_Segmentize($2, 0.00002), 0.0002));
$_$;


--
-- Name: owl_generatechanges(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION owl_generatechanges(bigint) RETURNS change[]
    LANGUAGE plpgsql
    AS $_$
DECLARE
  min_tstamp timestamp without time zone;
  max_tstamp timestamp without time zone;
  moved_nodes_ids bigint[];
  row_count int;

BEGIN
  RAISE NOTICE '% -- Generating changes for changeset %', clock_timestamp(), $1;

  CREATE TEMPORARY TABLE _tmp_changeset_nodes ON COMMIT DROP AS
  SELECT
    $1,
    n.tstamp,
    n.changeset_id,
    'N'::element_type AS type,
    n.id,
    n.version,
    CASE
      WHEN n.version = 1 THEN 'CREATE'::action
      WHEN n.version > 1 AND n.visible THEN 'MODIFY'::action
      WHEN NOT n.visible THEN 'DELETE'::action
    END AS el_action,
    NOT OWL_Equals(n.geom, prev.geom) AS geom_changed,
    n.tags != prev.tags AS tags_changed,
    NULL::boolean AS nodes_changed,
    NULL::boolean AS members_changed,
    CASE WHEN NOT n.visible THEN NULL ELSE n.geom END AS geom,
    CASE WHEN NOT n.visible OR NOT OWL_Equals(n.geom, prev.geom) THEN prev.geom ELSE NULL END AS prev_geom,
    n.tags,
    prev.tags AS prev_tags,
    NULL::bigint[] AS nodes,
    NULL::bigint[] AS prev_nodes
  FROM nodes n
  LEFT JOIN nodes prev ON (prev.id = n.id AND prev.version = n.version - 1)
  WHERE n.changeset_id = $1 AND (prev.version IS NOT NULL OR n.version = 1);

  CREATE TEMPORARY TABLE _tmp_moved_nodes ON COMMIT DROP AS
  SELECT * FROM _tmp_changeset_nodes n WHERE n.version > 1 AND n.geom_changed AND n.el_action != 'DELETE';

  SELECT MAX(x.tstamp), MIN(x.tstamp) - INTERVAL '1 second'
  INTO max_tstamp, min_tstamp
  FROM (
    SELECT n.tstamp
    FROM nodes n
    WHERE n.changeset_id = $1
    UNION
    SELECT w.tstamp
    FROM ways w
    WHERE w.changeset_id = $1
  ) x;

  moved_nodes_ids := (SELECT array_agg(id) FROM _tmp_moved_nodes);

  RAISE NOTICE '% --   Prepared data (min = %, max = %, moved nodes = %)', clock_timestamp(),
    min_tstamp, max_tstamp, (SELECT COUNT(*) FROM _tmp_moved_nodes);

  CREATE TEMPORARY TABLE _tmp_result ON COMMIT DROP AS
  SELECT *
  FROM _tmp_changeset_nodes n
  WHERE (n.el_action IN ('CREATE', 'DELETE') OR n.tags_changed OR n.geom_changed) AND
    (OWL_RemoveTags(n.tags) != ''::hstore OR OWL_RemoveTags(n.prev_tags) != ''::hstore);

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
    'CREATE',
    NULL,
    NULL,
    NULL,
    NULL,
    w.geom,
    NULL,
    w.tags,
    NULL,
    w.nodes,
    NULL
  FROM (
    SELECT w.*, OWL_MakeLine(w.nodes, max_tstamp) AS geom
    FROM ways w
    WHERE w.changeset_id = $1 AND w.version = 1) w
  WHERE w.geom IS NOT NULL;

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
    'MODIFY',
    w.geom_changed,
    w.tags_changed,
    w.nodes_changed,
    NULL,
    CASE WHEN w.geom_changed AND NOT w.tags_changed AND NOT w.nodes_changed THEN
      OWL_MakeMinimalLine(w.nodes, max_tstamp, (SELECT array_agg(id) FROM _tmp_changeset_nodes n WHERE w.nodes @> ARRAY[n.id]))
    ELSE
      OWL_MakeLine(w.nodes, max_tstamp)
    END,
    CASE WHEN w.geom_changed AND NOT w.tags_changed AND NOT w.nodes_changed THEN
      OWL_MakeMinimalLine(w.prev_nodes, min_tstamp, (SELECT array_agg(id) FROM _tmp_changeset_nodes n WHERE w.prev_nodes @> ARRAY[n.id]))
    ELSE
      CASE WHEN w.visible AND NOT w.geom_changed THEN NULL ELSE OWL_MakeLine(w.prev_nodes, min_tstamp) END
    END,
    w.tags,
    w.prev_tags,
    w.nodes,
    CASE WHEN w.nodes = w.prev_nodes THEN NULL ELSE w.prev_nodes END
  FROM (
    SELECT w.*,
      prev.tags AS prev_tags,
      prev.nodes AS prev_nodes,
      NOT OWL_Equals(OWL_MakeLine(w.nodes, w.tstamp), OWL_MakeLine(prev.nodes, prev.tstamp)) AS geom_changed,
      CASE WHEN NOT w.visible OR w.version = 1 THEN NULL ELSE w.tags != prev.tags END AS tags_changed,
      w.nodes != prev.nodes AS nodes_changed
    FROM ways w
    INNER JOIN ways prev ON (prev.id = w.id AND prev.version = w.version - 1)
    WHERE w.changeset_id = $1 AND w.visible) w
  WHERE w.geom_changed IS NOT NULL AND (w.geom_changed OR w.tags_changed OR w.nodes_changed);

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
    'DELETE',
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    w.prev_geom,
    w.tags,
    w.prev_tags,
    w.nodes,
    w.prev_nodes
  FROM (
    SELECT w.*,
      prev.tags AS prev_tags,
      prev.nodes AS prev_nodes,
      OWL_MakeLine(prev.nodes, max_tstamp) AS prev_geom
    FROM ways w
    INNER JOIN ways prev ON (prev.id = w.id AND prev.version = w.version - 1)
    WHERE w.changeset_id = $1 AND NOT w.visible) w
  WHERE w.prev_geom IS NOT NULL;

  GET DIAGNOSTICS row_count = ROW_COUNT;
  RAISE NOTICE '% --   Deleted ways done (%)', clock_timestamp(), row_count;

  -- Affected ways

  INSERT INTO _tmp_result
  SELECT
    $1,
    w.tstamp,
    w.changeset_id,
    'W'::element_type AS type,
    w.id,
    version,
    'AFFECT'::action,
    true,
    false,
    false,
    NULL,
    w.geom,
    w.prev_geom,
    w.tags,
    NULL,
    w.nodes,
    NULL
  FROM (
    SELECT
      *,
      OWL_MakeMinimalLine(w.nodes, max_tstamp, array_intersect(w.nodes, moved_nodes_ids)) AS geom,
      OWL_MakeMinimalLine(w.nodes, min_tstamp, array_intersect(w.nodes, moved_nodes_ids)) AS prev_geom
      --OWL_MakeLine(w.nodes, max_tstamp) AS geom,
      --OWL_MakeLine(w.nodes, min_tstamp) AS prev_geom
    FROM ways w
    WHERE w.nodes && moved_nodes_ids AND
      w.version = (SELECT version FROM ways WHERE id = w.id AND tstamp <= max_tstamp ORDER BY version DESC LIMIT 1) AND
      w.changeset_id != $1) w; -- AND
      --OWL_MakeLine(w.nodes, max_tstamp) IS NOT NULL AND
      --(w.version = 1 OR OWL_MakeLine(w.nodes, min_tstamp) IS NOT NULL)) w;

  GET DIAGNOSTICS row_count = ROW_COUNT;
  RAISE NOTICE '% --   Affected ways done (%)', clock_timestamp(), row_count;

  RAISE NOTICE '% -- Returning % change(s)', clock_timestamp(), (SELECT COUNT(*) FROM _tmp_result);

  RETURN (SELECT array_agg(x.c) FROM (SELECT ROW(
    (row_number() OVER ())::int,
    tstamp,
    type,
    el_action,
    id,
    version,
    tags,
    prev_tags,
    geom,
    prev_geom
  )::change AS c FROM _tmp_result ORDER BY tstamp) x);
END
$_$;


--
-- Name: owl_ispolygon(hstore); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION owl_ispolygon(hstore) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $_$
  SELECT $1 IS NOT NULL AND
    ($1 ? 'area' OR $1 ? 'landuse' OR $1 ? 'leisure' OR $1 ? 'amenity' OR $1 ? 'building')
$_$;


--
-- Name: owl_jointilegeometriesbychange(change[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION owl_jointilegeometriesbychange(change[]) RETURNS text[]
    LANGUAGE sql IMMUTABLE
    AS $_$
  WITH joined_arrays AS (
    SELECT (c.unnest).id AS change_id, (c.unnest).geom, GeometryType((c.unnest).geom) AS geom_type
    FROM (SELECT unnest($1)) c
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
$_$;


--
-- Name: owl_latlontotile(integer, geometry); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION owl_latlontotile(integer, geometry) RETURNS TABLE(x integer, y integer)
    LANGUAGE sql
    AS $_$
  SELECT
    floor((POW(2, $1) * ((ST_X($2) + 180) / 360)))::int AS tile_x,
    floor((1.0 - ln(tan(radians(ST_Y($2))) + 1.0 / cos(radians(ST_Y($2)))) / pi()) / 2.0 * POW(2, $1))::int AS tile_y;
$_$;


--
-- Name: owl_makeline(bigint[], timestamp without time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION owl_makeline(bigint[], timestamp without time zone) RETURNS geometry
    LANGUAGE plpgsql IMMUTABLE
    AS $_$
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
      ORDER BY id, tstamp DESC) q ON (q.id = x.node_id));

  -- Now check if the linestring has exactly the right number of points.
  IF ST_NumPoints(way_geom) != array_length($1, 1) THEN
    RETURN NULL;
  END IF;

  RETURN ST_MakeValid(way_geom);
END;
$_$;


--
-- Name: owl_makelinefromtmpnodes(bigint[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION owl_makelinefromtmpnodes(bigint[]) RETURNS geometry
    LANGUAGE plpgsql
    AS $_$
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
$_$;


--
-- Name: owl_makeminimalline(bigint[], timestamp without time zone, bigint[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION owl_makeminimalline(bigint[], timestamp without time zone, bigint[]) RETURNS geometry
    LANGUAGE plpgsql IMMUTABLE
    AS $_$
BEGIN
  RETURN OWL_MakeLine(
    (SELECT $1[MIN(idx($1, minimal_node)) - 2:MAX(idx($1, minimal_node)) + 2]
    FROM unnest($3) AS minimal_node), $2);
END
$_$;


--
-- Name: owl_mergechanges(change[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION owl_mergechanges(change[]) RETURNS change[]
    LANGUAGE sql
    AS $_$
  SELECT array_agg(x.ch ORDER BY (x.ch).id) FROM (
  SELECT DISTINCT ROW(
    id,
    tstamp,
    el_type,
    action,
    el_id,
    version,
    tags,
    prev_tags,
    NULL,
    NULL)::change ch
  FROM unnest($1) c
  GROUP BY c.id, c.tstamp, c.el_type, c.action, c.el_id, c.version, c.tags, c.prev_tags) x
$_$;


--
-- Name: owl_removetags(hstore); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION owl_removetags(hstore) RETURNS hstore
    LANGUAGE sql IMMUTABLE STRICT
    AS $_$
  SELECT $1 - ARRAY['created_by', 'source']
$_$;


--
-- Name: owl_updatechangeset(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION owl_updatechangeset(bigint) RETURNS void
    LANGUAGE plpgsql
    AS $_$
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
$_$;


--
-- Name: array_accum(anyarray); Type: AGGREGATE; Schema: public; Owner: -
--

CREATE AGGREGATE array_accum(anyarray) (
    SFUNC = array_cat,
    STYPE = anyarray,
    INITCOND = '{}'
);


SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: changeset_tiles; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE changeset_tiles (
    changeset_id bigint NOT NULL,
    tstamp timestamp without time zone NOT NULL,
    x integer NOT NULL,
    y integer NOT NULL,
    zoom integer NOT NULL,
    changes change[] NOT NULL
);


--
-- Name: changesets; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE changesets (
    id bigint NOT NULL,
    user_id bigint,
    user_name character varying(255),
    created_at timestamp without time zone NOT NULL,
    closed_at timestamp without time zone,
    open boolean NOT NULL,
    tags hstore NOT NULL,
    entity_changes integer[],
    num_changes integer,
    bbox geometry
);


--
-- Name: nodes; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE nodes (
    id bigint NOT NULL,
    version integer NOT NULL,
    rev integer NOT NULL,
    visible boolean NOT NULL,
    current boolean NOT NULL,
    user_id integer NOT NULL,
    tstamp timestamp without time zone NOT NULL,
    changeset_id bigint NOT NULL,
    tags hstore NOT NULL,
    geom geometry(Point,4326)
);


--
-- Name: relation_members; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE relation_members (
    relation_id bigint NOT NULL,
    version bigint NOT NULL,
    member_id bigint NOT NULL,
    member_type character(1) NOT NULL,
    member_role text NOT NULL,
    sequence_id integer NOT NULL
);


--
-- Name: relations; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE relations (
    id bigint NOT NULL,
    version integer NOT NULL,
    rev integer NOT NULL,
    visible boolean NOT NULL,
    current boolean NOT NULL,
    user_id integer NOT NULL,
    tstamp timestamp without time zone NOT NULL,
    changeset_id bigint NOT NULL,
    tags hstore NOT NULL
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE users (
    id integer NOT NULL,
    name text NOT NULL
);


--
-- Name: ways; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE ways (
    id bigint NOT NULL,
    version integer NOT NULL,
    visible boolean NOT NULL,
    current boolean NOT NULL,
    user_id integer NOT NULL,
    tstamp timestamp without time zone NOT NULL,
    changeset_id bigint NOT NULL,
    tags hstore NOT NULL,
    nodes bigint[] NOT NULL
);


--
-- Name: pk_changeset_tiles; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY changeset_tiles
    ADD CONSTRAINT pk_changeset_tiles PRIMARY KEY (changeset_id, x, y, zoom);


--
-- Name: pk_changesets; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY changesets
    ADD CONSTRAINT pk_changesets PRIMARY KEY (id);


--
-- Name: pk_nodes; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY nodes
    ADD CONSTRAINT pk_nodes PRIMARY KEY (id, version);


--
-- Name: pk_relation_members; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY relation_members
    ADD CONSTRAINT pk_relation_members PRIMARY KEY (relation_id, version, sequence_id);


--
-- Name: pk_relations; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY relations
    ADD CONSTRAINT pk_relations PRIMARY KEY (id, version);


--
-- Name: pk_users; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY users
    ADD CONSTRAINT pk_users PRIMARY KEY (id);


--
-- Name: pk_ways; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY ways
    ADD CONSTRAINT pk_ways PRIMARY KEY (id, version);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user",public;

