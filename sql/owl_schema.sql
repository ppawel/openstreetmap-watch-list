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

DROP TYPE IF EXISTS tile_type;
CREATE TYPE tile_type AS ENUM ('GEOMETRY', 'SUMMARY');

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
  type tile_type NOT NULL,
  changeset_id bigint,
  x int NOT NULL,
  y int NOT NULL,
  zoom int NOT NULL,
  geom geography,
  num_changesets int
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
CREATE INDEX idx_changeset_tiles_changeset_id ON changeset_tiles USING btree (changeset_id);
