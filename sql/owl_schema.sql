-- Database creation script for the OWL schema.
-- This script only contains the OWL-specific part, to get the full schema, see INSTALL.md!

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
  user_id bigint NOT NULL,
  created_at timestamp without time zone NOT NULL,
  closed_at timestamp without time zone NOT NULL,
  num_changes integer,
  tags hstore,
  geom geography -- Aggregated geometry for this changeset's changes. Suitable for ST_Intersection/ST_Intersects calls.
);

-- Create a table for changes.
CREATE TABLE changes (
  id bigserial PRIMARY KEY,
  user_id bigint NOT NULL,
  version int NOT NULL,
  changeset_id bigint NOT NULL REFERENCES changesets,
  tstamp timestamp without time zone NOT NULL,
  action action NOT NULL,
  change_type change_type NOT NULL,
  el_type element_type NOT NULL,
  el_id bigint NOT NULL,
  tags hstore, -- If action is CREATE or DELETE, contains new/deleted element tags;
               -- If action is MODIFY, contains tags of element existing in the database (if it exists - otherwise NULL).
  new_tags hstore, -- If action is MODIFY, contains new tags of the element; otherwise NULL.
  geom geography, -- If action is CREATE or DELETE, contains new/deleted element geometry;
                  -- If action is MODIFY, contains geometry of element existing in the database (if it exists - otherwise NULL).
  new_geom geography -- If action is MODIFY, contains new geometry of the element; otherwise NULL.
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
