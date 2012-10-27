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
CREATE TYPE change_type AS ENUM ('CREATE', 'DELETE', 'CHANGE_GEOM', 'CHANGE_TAGS');

-- Create a table for changesets.
CREATE TABLE changesets (
  id bigserial PRIMARY KEY,
  user_id bigint NOT NULL REFERENCES users,
  created_at timestamp without time zone NOT NULL,
  closed_at timestamp without time zone NOT NULL,
  num_changes integer NOT NULL DEFAULT 0,
  tags hstore,
  geom geography,
  change_count int
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
  geom geography,
  new_geom geography
);

CREATE INDEX idx_changes_changeset_id ON changes USING btree (changeset_id);
CREATE INDEX idx_changesets_geom ON changesets USING gist (geom);
CREATE INDEX idx_changesets_created_at ON changesets USING btree (created_at);

DROP FUNCTION IF EXISTS OWL_UpdateChangesetGeom(bigint);
CREATE FUNCTION OWL_UpdateChangesetGeom(bigint) RETURNS void AS $$
DECLARE
  changeset_geom geography;
BEGIN

changeset_geom := (
  SELECT ST_Collect(DISTINCT g.geom)::geography
  FROM
  (
    SELECT geom::geometry FROM changes WHERE changeset_id = $1
    UNION
    SELECT new_geom::geometry FROM changes WHERE changeset_id = $1
  ) g);

UPDATE changesets SET geom = changeset_geom WHERE id = $1;

END;
$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS OWL_UpdateChangesetChangeCount(bigint);
CREATE FUNCTION OWL_UpdateChangesetChangeCount(bigint) RETURNS void AS $$
UPDATE changesets cs SET change_count = (SELECT COUNT(*) FROM changes c WHERE c.changeset_id = cs.id);
$$ LANGUAGE SQL;

DROP FUNCTION IF EXISTS OWL_UpdateAllChangesetsGeom();
CREATE FUNCTION OWL_UpdateAllChangesetsGeom() RETURNS void AS $$
DECLARE
  changeset_id bigint;
BEGIN
FOR changeset_id IN SELECT id FROM changesets LOOP
  RAISE NOTICE '% Changeset %', clock_timestamp(), changeset_id;
  PERFORM Osmosis_ChangeDb_UpdateChangesetGeom(changeset_id);
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
