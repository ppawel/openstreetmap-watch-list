DROP FUNCTION IF EXISTS OWL_GetChangesetData(int);
DROP FUNCTION IF EXISTS OWL_UpdateChangeset(bigint);
DROP FUNCTION IF EXISTS OWL_AggregateChangeset(bigint, int, int);

--
-- OWL_GetChangesetData
--
CREATE FUNCTION OWL_GetChangesetData(int) RETURNS
	TABLE(
		type char(2),
		id bigint,
		version int,
		tstamp timestamp without time zone,
		tags hstore,
		geom geometry,
		prev_version int,
		prev_tags hstore,
		prev_geom geometry) AS $$
  WITH affected_nodes AS (
  SELECT
    'N'::text AS type,
    n.id,
    n.version,
    n.tstamp,
    n.tags,
    n.geom,
    prev.version AS prev_version,
    prev.tags AS prev_tags,
    prev.geom AS prev_geom
  FROM nodes n
  LEFT JOIN nodes prev ON (prev.id = n.id AND prev.version = n.version - 1)
  WHERE n.changeset_id = $1
  )

  SELECT
    'W' AS type,
    w.id,
    w.version,
    w.tstamp,
    w.tags,
    (SELECT ST_MakeLine(geom) FROM (SELECT geom FROM nodes wn WHERE wn.id IN (SELECT unnest(w.nodes)) ORDER BY wn.version DESC) x),
    prev.version AS prev_version,
    prev.tags AS prev_tags,
    (SELECT ST_MakeLine(geom) FROM (SELECT geom FROM nodes wn WHERE wn.id IN (SELECT unnest(prev.nodes)) AND wn.tstamp < prev.tstamp ORDER BY wn.version DESC) x)
  FROM ways w
  INNER JOIN ways prev ON (prev.id = w.id AND prev.version = w.version - 1)
  WHERE w.nodes && (SELECT array_agg(id) FROM affected_nodes an WHERE (an.tags IS NULL AND an.prev_tags IS NULL) OR an.tags = an.prev_tags)

  UNION ALL

  SELECT *
  FROM affected_nodes
  WHERE (tags IS NOT NULL OR prev_tags IS NOT NULL) AND tags != prev_tags

  UNION ALL

  SELECT
    'W' AS type,
    w.id,
    w.version,
    w.tstamp,
    w.tags,
    (SELECT ST_MakeLine(geom) FROM (SELECT geom FROM nodes wn WHERE wn.id IN (SELECT unnest(w.nodes)) ORDER BY wn.version DESC) x),
    prev.version AS prev_version,
    prev.tags AS prev_tags,
    (SELECT ST_MakeLine(geom) FROM (SELECT geom FROM nodes wn WHERE wn.id IN (SELECT unnest(prev.nodes)) AND wn.tstamp < prev.tstamp ORDER BY wn.version DESC) x)
  FROM ways w
  INNER JOIN ways prev ON (prev.id = w.id AND prev.version = w.version - 1)
  WHERE w.changeset_id = $1
$$ LANGUAGE sql;

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

CREATE FUNCTION OWL_AggregateChangeset(bigint, int, int) RETURNS void AS $$
DECLARE
  subtiles_per_tile bigint;

BEGIN
  subtiles_per_tile := POW(2, $2) / POW(2, $3);

  DELETE FROM changeset_tiles WHERE changeset_id = $1 AND zoom = $3;

  INSERT INTO changeset_tiles (changeset_id, tstamp, x, y, zoom, geom)
  SELECT $1, MAX(tstamp), x/subtiles_per_tile, y/subtiles_per_tile, $3, ST_SetSRID(ST_Extent(geom), 4326)
  FROM changeset_tiles
  WHERE changeset_id = $1 AND zoom = $2
  GROUP BY x/subtiles_per_tile, y/subtiles_per_tile;
END;
$$ LANGUAGE plpgsql;
