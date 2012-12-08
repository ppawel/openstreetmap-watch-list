-- Database creation script for the OWL schema.

DROP TABLE IF EXISTS nodes;
DROP TABLE IF EXISTS ways;
DROP TABLE IF EXISTS tiles;
DROP TABLE IF EXISTS changesets;
DROP TABLE IF EXISTS relation_members;
DROP TABLE IF EXISTS relations;
DROP TABLE IF EXISTS users;

DROP TYPE IF EXISTS element_type CASCADE;
CREATE TYPE element_type AS ENUM ('N', 'W', 'R');

DROP TYPE IF EXISTS action CASCADE;
CREATE TYPE action AS ENUM ('CREATE', 'MODIFY', 'DELETE');

-- Create a table for changesets.
CREATE TABLE changesets (
  id bigint NOT NULL,
  user_id bigint NOT NULL,
  created_at timestamp without time zone NOT NULL,
  closed_at timestamp without time zone, -- If NULL, changeset is still open for business.
  tags hstore NOT NULL,
  entity_changes int[9], -- For each element type (N, W, R) holds number of actions (CREATE, MODIFY, DELETE) in this changeset.
  bbox geometry -- Bounding box of all changes for this changeset.
);

-- Create a table for OWL tiles.
CREATE TABLE tiles (
  changeset_id bigint NOT NULL,
  tstamp timestamp without time zone,
  x int NOT NULL,
  y int NOT NULL,
  zoom int NOT NULL,
  changes bigint[] NOT NULL,
  geom geometry(GEOMETRY, 4326) NOT NULL
);

-- Create a table for nodes.
CREATE TABLE nodes (
    id bigint NOT NULL,
    version int NOT NULL,
    user_id int NOT NULL,
    tstamp timestamp without time zone NOT NULL,
    changeset_id bigint NOT NULL,
    tags hstore NOT NULL,
    geom geometry(POINT, 4326) NOT NULL
);

-- Create a table for ways.
CREATE TABLE ways (
    id bigint NOT NULL,
    version int NOT NULL,
    user_id int NOT NULL,
    tstamp timestamp without time zone NOT NULL,
    changeset_id bigint NOT NULL,
    tags hstore NOT NULL,
    nodes bigint[] NOT NULL,
    linestring geometry(LINESTRING, 4326) NOT NULL
);

-- Create a table for relations.
CREATE TABLE relations (
    id bigint NOT NULL,
    version int NOT NULL,
    user_id int NOT NULL,
    tstamp timestamp without time zone NOT NULL,
    changeset_id bigint NOT NULL,
    tags hstore NOT NULL
);

-- Create a table for representing relation member relationships.
CREATE TABLE relation_members (
    relation_id bigint NOT NULL,
    relation_version bigint NOT NULL,
    member_id bigint NOT NULL,
    member_type character(1) NOT NULL,
    member_role text NOT NULL,
    sequence_id int NOT NULL
);

-- Create a table for users.
CREATE TABLE users (
    id int NOT NULL,
    name text NOT NULL
);
