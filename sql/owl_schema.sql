-- Database creation script for the OWL schema.
-- This script only contains OWL-specific part, to get the full schema run pgsnapshot_schema_0.6.sql first!

-- Drop all tables if they exist.
DROP TABLE IF EXISTS changes;
DROP TABLE IF EXISTS changesets;

-- Create a table for changes.
CREATE TABLE changes (
    id bigserial NOT NULL,
    user_id int NOT NULL,
    version int NOT NULL,
    changeset_id bigint NOT NULL,
    tstamp timestamp without time zone NOT NULL,
    action character varying(10) NOT NULL,
    element_type character varying(10) NOT NULL,
    element_id bigint NOT NULL,
    old_tags hstore,
    new_tags hstore,
    old_geom geometry,
    new_geom geometry
);

-- Create a table for changesets.
CREATE TABLE changesets (
  id bigserial NOT NULL,
  user_id bigint NOT NULL,
  created_at timestamp without time zone NOT NULL,
  closed_at timestamp without time zone NOT NULL,
  num_changes integer NOT NULL DEFAULT 0,
  tags hstore,
  geom geometry
);

ALTER TABLE ONLY changes ADD CONSTRAINT pk_changes PRIMARY KEY (id);
ALTER TABLE ONLY changesets ADD CONSTRAINT pk_changesets PRIMARY KEY (id);

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
    SELECT (ST_Dump(old_geom)).geom FROM changes WHERE changeset_id = $1 AND element_type = 'Way'
    UNION ALL
    SELECT (ST_Dump(new_geom)).geom FROM changes WHERE changeset_id = $1 AND element_type = 'Way'
    UNION ALL
    SELECT ST_MakeLine(old_geom, old_geom) FROM changes WHERE changeset_id = $1 AND element_type = 'Node'
    UNION ALL
    SELECT ST_MakeLine(new_geom, new_geom) FROM changes WHERE changeset_id = $1 AND element_type = 'Node'
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
