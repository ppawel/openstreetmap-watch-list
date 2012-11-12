-- Database creation script for the OWL schema.
-- This script only contains the OWL-specific part, to get the full schema, see INSTALL.md!

-- Drop all tables if they exist.
DROP TABLE IF EXISTS changes;
DROP TABLE IF EXISTS changeset_tiles;
DROP TABLE IF EXISTS changesets;
DROP TABLE IF EXISTS summary_tiles;

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
  last_tiled_at timestamp without time zone,
  num_changes integer,
  tags hstore
);

-- Create a table for changeset tiles.
CREATE TABLE changeset_tiles (
  changeset_id bigint,
  tstamp timestamp without time zone,
  x int NOT NULL,
  y int NOT NULL,
  zoom int NOT NULL,
  geom geometry(GEOMETRY, 4326),
  PRIMARY KEY (changeset_id, x, y, zoom)
);

-- Create a table for changes.
CREATE TABLE changes (
  id bigserial PRIMARY KEY,
  el_type element_type NOT NULL,
  el_id bigint NOT NULL,
  version int NOT NULL,
  changeset_id bigint NOT NULL,
  tstamp timestamp without time zone NOT NULL,
  action action NOT NULL,
  changed_tags boolean NOT NULL,
  changed_geom boolean NOT NULL,
  changed_members boolean NOT NULL, -- Always false if el_type = NODE.
  current_tags hstore, -- If action is DELETE or MODIFY, contains tags of element existing in the database (if it exists); otherwise NULL.
  new_tags hstore, -- If action is CREATE or MODIFY, contains new tags of the element; otherwise NULL.
  current_geom geometry(GEOMETRY, 4326), -- If action is DELETE or MODIFY, contains tags of element existing in the database (if it exists); otherwise NULL.
  new_geom geometry(GEOMETRY, 4326) -- If action is CREATE or MODIFY, contains new geometry(GEOMETRY, 4326) of the element; otherwise NULL.
);

-- Create a table for summary tiles.
CREATE TABLE summary_tiles (
  x int NOT NULL,
  y int NOT NULL,
  zoom int NOT NULL,
  num_changesets int,
  PRIMARY KEY (x, y, zoom)
);

CREATE INDEX idx_changes_changeset_id ON changes USING btree (changeset_id);
CREATE INDEX idx_changes_current_geom ON changes USING gist (current_geom);
CREATE INDEX idx_changes_new_geom ON changes USING gist (new_geom);
CREATE INDEX idx_changesets_geom ON changesets USING gist (geom);
CREATE INDEX idx_changesets_created_at ON changesets USING btree (created_at);
CREATE INDEX idx_changesets_last_tiled_at ON changesets USING btree (last_tiled_at);
CREATE INDEX idx_changesets_num_changes ON changesets USING btree (num_changes);
CREATE INDEX idx_changeset_tiles_changeset_id ON changeset_tiles USING btree (changeset_id);
