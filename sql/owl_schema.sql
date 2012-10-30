-- Database creation script for the OWL schema.
-- This script only contains the OWL-specific part, to get the full schema, see INSTALL.md!

-- Drop all tables if they exist.
DROP TABLE IF EXISTS changes;
DROP TABLE IF EXISTS changeset_tiles;
DROP TABLE IF EXISTS changesets;

DROP TYPE IF EXISTS element_type;
CREATE TYPE element_type AS ENUM ('N', 'W', 'R');

DROP TYPE IF EXISTS action;
CREATE TYPE action AS ENUM ('CREATE', 'MODIFY', 'DELETE');

-- Create a table for changesets.
CREATE TABLE changesets (
  id bigserial PRIMARY KEY,
  user_id bigint NOT NULL,
  created_at timestamp without time zone NOT NULL,
  closed_at timestamp without time zone NOT NULL,
  num_changes integer,
  tags hstore,
  geom geography -- Aggregated geometry for this changeset's changes. Suitable for ST_Intersection/ST_Intersects calls.
);

-- Create a table for changeset tiles.
CREATE TABLE changeset_tiles (
  changeset_id bigint REFERENCES changesets,
  tile_x int NOT NULL,
  tile_y int NOT NULL,
  zoom int NOT NULL,
  geom geography,
  PRIMARY KEY (changeset_id, tile_x, tile_y, zoom)
);

-- Create a table for changes.
CREATE TABLE changes (
  id bigserial PRIMARY KEY,
  el_type element_type NOT NULL,
  el_id bigint NOT NULL,
  version int NOT NULL,
  changeset_id bigint NOT NULL REFERENCES changesets,
  tstamp timestamp without time zone NOT NULL,
  action action NOT NULL,
  changed_tags boolean NOT NULL,
  changed_geom boolean NOT NULL,
  changed_members boolean NOT NULL, -- Always false if el_type = NODE.
  current_tags hstore, -- If action is DELETE or MODIFY, contains tags of element existing in the database (if it exists); otherwise NULL.
  new_tags hstore, -- If action is CREATE or MODIFY, contains new tags of the element; otherwise NULL.
  current_geom geography, -- If action is DELETE or MODIFY, contains tags of element existing in the database (if it exists); otherwise NULL.
  new_geom geography -- If action is CREATE or MODIFY, contains new geometry of the element; otherwise NULL.
);

CREATE INDEX idx_changes_changeset_id ON changes USING btree (changeset_id);
CREATE INDEX idx_changesets_geom ON changesets USING gist (geom);
CREATE INDEX idx_changesets_created_at ON changesets USING btree (created_at);
CREATE INDEX idx_changeset_tiless_changeset_id ON changeset_tiless USING btree (changeset_id);

DROP FUNCTION IF EXISTS OWL_UpdateChangesetGeom(bigint);
CREATE FUNCTION OWL_UpdateChangesetGeom(bigint) RETURNS void AS $$
DECLARE
  changeset_geom geography;
BEGIN

changeset_geom := (
  SELECT ST_Collect(DISTINCT g.geom)::geography
  FROM
  (
    SELECT current_geom::geometry AS geom FROM changes WHERE changeset_id = $1
    UNION
    SELECT new_geom::geometry AS geom FROM changes WHERE changeset_id = $1
  ) g);

UPDATE changesets SET geom = changeset_geom WHERE id = $1;

END;
$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS OWL_UpdateChangesetChangeCount(bigint);
CREATE FUNCTION OWL_UpdateChangesetChangeCount(bigint) RETURNS void AS $$
  UPDATE
    changesets cs
  SET num_changes = (SELECT COUNT(*) FROM changes c WHERE c.changeset_id = cs.id)
  WHERE cs.id = $1;
$$ LANGUAGE SQL;

DROP FUNCTION IF EXISTS OWL_UpdateAllChangesetsGeom();
CREATE FUNCTION OWL_UpdateAllChangesetsGeom() RETURNS void AS $$
DECLARE
  changeset_id bigint;
BEGIN
FOR changeset_id IN SELECT id FROM changesets LOOP
  RAISE NOTICE '% Changeset %', clock_timestamp(), changeset_id;
  PERFORM OWL_UpdateChangesetGeom(changeset_id);
END LOOP;
END;
$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS OWL_UpdateAllChangesetsChangeCount();
CREATE FUNCTION OWL_UpdateAllChangesetsChangeCount() RETURNS void AS $$
DECLARE
  changeset_id bigint;
BEGIN
FOR changeset_id IN SELECT id FROM changesets LOOP
  RAISE NOTICE '% Changeset %', clock_timestamp(), changeset_id;
  PERFORM OWL_UpdateChangesetChangeCount(changeset_id);
END LOOP;
END;
$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS OWL_LatLonToTileXY(int, geometry);
CREATE FUNCTION OWL_LatLonToTileXY(int, geometry) RETURNS record AS $$
  SELECT
    (POW(2, $1) * ((ST_X($2) + 180) / 360))::int AS tile_x,
    (POW(2, $1) * ((ST_Y(ST_Transform($2, 900913)) + 20037508.34) / (20037508.34 * 2)))::int AS tile_y;
$$ LANGUAGE SQL;

DROP FUNCTION IF EXISTS OWL_TileXYToLatLon(int, int, int);
CREATE FUNCTION OWL_TileXYToLatLon(int, int, int) RETURNS geometry AS $$
  SELECT ST_MakePoint(
    $2 / POW(2, $1) * 360 - 180,
    ST_Y(ST_Transform(ST_SetSRID(ST_MakePoint(0, $3 / POW(2, $1) * 20037508.34 * 2 - 20037508.34), 900913), 4326)));
$$ LANGUAGE SQL;

DROP FUNCTION IF EXISTS OWL_TileXYToBOX(int, int, int);
CREATE FUNCTION OWL_TileXYToBOX(int, int, int) RETURNS box2d AS $$
  SELECT ST_MakeBox2D(
    ST_MakePoint(ST_X(OWL_TileXYToLatLon($1, $2, $3)), ST_Y(OWL_TileXYToLatLon($1, $2 + 1, $3 + 1))),
    ST_MakePoint(ST_X(OWL_TileXYToLatLon($1, $2 + 1, $3 + 1)), ST_Y(OWL_TileXYToLatLon($1, $2, $3)))
    );
$$ LANGUAGE SQL;

DROP FUNCTION IF EXISTS OWL_GenerateChangesetTiles(bigint);
CREATE FUNCTION OWL_GenerateChangesetTiles(bigint) RETURNS void AS $$
DECLARE
  changeset_geom geometry;
  tile_geom geometry;
  tile_xy_topleft record;
  tile_xy_bottomright record;
  tile_box box2d;
  tile_latlon1 geometry;
  tile_latlon2 geometry;
  i int;
  j int;
  zoom int;

BEGIN
  zoom := 2;

  DELETE FROM changeset_tiles WHERE changeset_id = $1;

  changeset_geom := (SELECT geom::geometry FROM changesets WHERE id = $1);

  IF changeset_geom IS NULL OR ST_IsEmpty(changeset_geom) THEN
    RETURN;
  END IF;

  --RAISE NOTICE '%', ST_astext(changeset_geom);

  tile_xy_topleft := OWL_LatLonToTileXY(zoom,
    ST_SetSRID(ST_MakePoint(ST_XMin(changeset_geom), ST_YMin(changeset_geom)), 4326));

  tile_xy_bottomright := OWL_LatLonToTileXY(zoom,
    ST_SetSRID(ST_MakePoint(ST_XMax(changeset_geom), ST_YMax(changeset_geom)), 4326));

  FOR i IN tile_xy_topleft.tile_x..tile_xy_bottomright.tile_x LOOP
    FOR j IN tile_xy_topleft.tile_y..tile_xy_bottomright.tile_y LOOP
      tile_box := OWL_TileXYToBOX(zoom, i, j);
      RAISE NOTICE 'Processing tile % % % ...', i, j, tile_box;
      tile_geom := ST_Intersection(ST_SetSRID(tile_box, 4326), changeset_geom);

      IF NOT ST_IsEmpty(tile_geom) THEN
        RAISE NOTICE 'Got ourselves a tile geometry';

        INSERT INTO changeset_tiles (changeset_id, zoom, tile_x, tile_y, geom)
          VALUES ($1, zoom, i, j, tile_geom);
      END IF;
    END LOOP;
  END LOOP;
END;
$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS OWL_UpdateAllChangesetsTiles();
CREATE FUNCTION OWL_UpdateAllChangesetsTiles() RETURNS void AS $$
DECLARE
  changeset_id bigint;
BEGIN
FOR changeset_id IN SELECT id FROM changesets ORDER BY id LOOP
  RAISE NOTICE '% Changeset %', clock_timestamp(), changeset_id;
  PERFORM OWL_GenerateChangesetTiles(changeset_id);
END LOOP;
END;
$$ LANGUAGE plpgsql;
