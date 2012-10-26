-- Database creation script for the OWL schema.
-- This script only contains OWL-specific part, to get the full schema run pgsnapshot_schema_0.6.sql first!

-- Drop all tables if they exist.
DROP TABLE IF EXISTS changes;
DROP TABLE IF EXISTS changesets;

DROP TYPE IF EXISTS element_type;
CREATE TYPE element_type AS ENUM ('N', 'W', 'R');

DROP TYPE IF EXISTS action;
CREATE TYPE action AS ENUM ('CREATE', 'MODIFY', 'DELETE');

DROP TYPE IF EXISTS change_type;
CREATE TYPE change_type AS ENUM ('NEW', 'DELETE', 'CHANGE_GEOM', 'CHANGE_TAGS');

-- Create a table for changesets.
CREATE TABLE changesets (
  id bigserial PRIMARY KEY,
  user_id bigint NOT NULL REFERENCES users,
  created_at timestamp without time zone NOT NULL,
  closed_at timestamp without time zone NOT NULL,
  num_changes integer NOT NULL DEFAULT 0,
  tags hstore,
  geom geometry
);

-- Create a table for changes.
CREATE TABLE changes (
  id bigserial PRIMARY KEY,
  user_id bigint NOT NULL REFERENCES users,
  version int NOT NULL,
  changeset_id bigint NOT NULL REFERENCES changesets,
  tstamp timestamp without time zone NOT NULL,
  action action NOT NULL,
  change_type change_type NOT NULL,
  el_type element_type NOT NULL,
  el_id bigint NOT NULL,
  tags hstore,
  new_tags hstore,
  geom geometry,
  new_geom geometry
);

DROP INDEX IF EXISTS idx_changes_changeset_id;
CREATE INDEX idx_changes_changeset_id ON changes USING btree (changeset_id);

DROP INDEX IF EXISTS idx_changesets_geom;
CREATE INDEX idx_changesets_geom ON changesets USING gist (geom);

DROP INDEX IF EXISTS idx_changesets_created_at;
CREATE INDEX idx_changesets_created_at ON changesets USING btree (created_at);

DROP FUNCTION IF EXISTS Osmosis_ChangeDb_UpdateChangesetGeom(bigint);
CREATE FUNCTION Osmosis_ChangeDb_UpdateChangesetGeom(bigint) RETURNS void AS $$
DECLARE
  changeset_geom geometry;

BEGIN

changeset_geom := (
  SELECT st_collect(g.geom)
  FROM
  (
    SELECT (ST_Dump(geom)).geom FROM changes WHERE changeset_id = $1 AND el_type = 'Way'
    UNION
    SELECT (ST_Dump(new_geom)).geom FROM changes WHERE changeset_id = $1 AND el_type = 'Way'
    UNION
    SELECT ST_Boundary(ST_Buffer(geom, 0.00000001, 1)) FROM changes WHERE changeset_id = $1 AND el_type = 'Node'
    UNION
    SELECT ST_Boundary(ST_Buffer(new_geom, 0.00000001, 1)) FROM changes WHERE changeset_id = $1 AND el_type = 'Node'
  ) g);

UPDATE changesets SET geom = changeset_geom WHERE id = $1;

END;
$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS Osmosis_ChangeDb_UpdateAllChangesets();
CREATE FUNCTION Osmosis_ChangeDb_UpdateAllChangesets() RETURNS void AS $$
DECLARE
  changeset_id bigint;

BEGIN

FOR changeset_id IN SELECT id FROM changesets LOOP
  RAISE NOTICE '% Changeset %', clock_timestamp(), changeset_id;
  PERFORM Osmosis_ChangeDb_UpdateChangesetGeom(changeset_id);
END LOOP;

END;
$$ LANGUAGE plpgsql;
