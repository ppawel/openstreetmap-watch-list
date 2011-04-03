--
-- PostgreSQL database dump
--

SET client_encoding = 'UTF8';
SET standard_conforming_strings = off;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET escape_string_warning = off;

SET search_path = public, pg_catalog;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: catchup_history; Type: TABLE; Schema: public; Owner: matt; Tablespace: 
--

CREATE TABLE catchup_history (
    "time" timestamp without time zone NOT NULL,
    local_seq bigint NOT NULL,
    remote_seq bigint NOT NULL,
    local_time timestamp without time zone NOT NULL,
    remote_time timestamp without time zone NOT NULL
);


ALTER TABLE public.catchup_history OWNER TO matt;

SET default_tablespace = home;

--
-- Name: changes; Type: TABLE; Schema: public; Owner: matt; Tablespace: home
--

CREATE TABLE changes (
    elem_type nwr_enum NOT NULL,
    id integer NOT NULL,
    version integer NOT NULL,
    changeset integer NOT NULL,
    change_type change_enum NOT NULL,
    tile bigint NOT NULL,
    "time" timestamp without time zone NOT NULL
);


ALTER TABLE public.changes OWNER TO matt;

SET default_tablespace = '';

--
-- Name: changeset_details; Type: TABLE; Schema: public; Owner: matt; Tablespace: 
--

CREATE TABLE changeset_details (
    id bigint NOT NULL,
    uid bigint NOT NULL,
    closed boolean DEFAULT false NOT NULL,
    last_seen timestamp without time zone NOT NULL,
    comment text,
    created_by text,
    bot_tag boolean
);


ALTER TABLE public.changeset_details OWNER TO matt;

SET default_tablespace = home;

--
-- Name: changesets; Type: TABLE; Schema: public; Owner: matt; Tablespace: home
--

CREATE TABLE changesets (
    id bigint NOT NULL,
    uid bigint NOT NULL,
    num bigint NOT NULL
);


ALTER TABLE public.changesets OWNER TO matt;

--
-- Name: dupe_node_history; Type: TABLE; Schema: public; Owner: matt; Tablespace: home
--

CREATE TABLE dupe_node_history (
    num bigint NOT NULL,
    "time" timestamp without time zone NOT NULL
);


ALTER TABLE public.dupe_node_history OWNER TO matt;

--
-- Name: dupe_nodes; Type: TABLE; Schema: public; Owner: matt; Tablespace: home
--

CREATE TABLE dupe_nodes (
    geom geometry,
    tile bigint NOT NULL,
    CONSTRAINT enforce_dims_geom CHECK ((st_ndims(geom) = 2)),
    CONSTRAINT enforce_geotype_geom CHECK (((geometrytype(geom) = 'POINT'::text) OR (geom IS NULL))),
    CONSTRAINT enforce_srid_geom CHECK ((st_srid(geom) = 900913))
);


ALTER TABLE public.dupe_nodes OWNER TO matt;

SET default_tablespace = '';

SET default_with_oids = true;

--
-- Name: geometry_columns; Type: TABLE; Schema: public; Owner: matt; Tablespace: 
--

CREATE TABLE geometry_columns (
    f_table_catalog character varying(256) NOT NULL,
    f_table_schema character varying(256) NOT NULL,
    f_table_name character varying(256) NOT NULL,
    f_geometry_column character varying(256) NOT NULL,
    coord_dimension integer NOT NULL,
    srid integer NOT NULL,
    type character varying(30) NOT NULL
);


ALTER TABLE public.geometry_columns OWNER TO matt;

SET default_tablespace = home;

SET default_with_oids = false;

--
-- Name: node_tags; Type: TABLE; Schema: public; Owner: matt; Tablespace: home
--

CREATE TABLE node_tags (
    id integer NOT NULL,
    k text NOT NULL,
    v text NOT NULL
);


ALTER TABLE public.node_tags OWNER TO matt;

--
-- Name: nodes; Type: TABLE; Schema: public; Owner: matt; Tablespace: home
--

CREATE TABLE nodes (
    id integer NOT NULL,
    version integer NOT NULL,
    changeset integer NOT NULL,
    lat integer NOT NULL,
    lon integer NOT NULL,
    tile bigint NOT NULL
);


ALTER TABLE public.nodes OWNER TO matt;

--
-- Name: relation_members; Type: TABLE; Schema: public; Owner: matt; Tablespace: home
--

CREATE TABLE relation_members (
    id integer NOT NULL,
    m_role text,
    m_type nwr_enum NOT NULL,
    m_id integer NOT NULL,
    seq integer NOT NULL
);


ALTER TABLE public.relation_members OWNER TO matt;

--
-- Name: relation_tags; Type: TABLE; Schema: public; Owner: matt; Tablespace: home
--

CREATE TABLE relation_tags (
    id integer NOT NULL,
    k text NOT NULL,
    v text NOT NULL
);


ALTER TABLE public.relation_tags OWNER TO matt;

--
-- Name: relations; Type: TABLE; Schema: public; Owner: matt; Tablespace: home
--

CREATE TABLE relations (
    id integer NOT NULL,
    version integer NOT NULL,
    changeset integer NOT NULL,
    tiles bytea
);


ALTER TABLE public.relations OWNER TO matt;

SET default_tablespace = '';

--
-- Name: spatial_ref_sys; Type: TABLE; Schema: public; Owner: matt; Tablespace: 
--

CREATE TABLE spatial_ref_sys (
    srid integer NOT NULL,
    auth_name character varying(256),
    auth_srid integer,
    srtext character varying(2048),
    proj4text character varying(2048)
);


ALTER TABLE public.spatial_ref_sys OWNER TO matt;

--
-- Name: users; Type: TABLE; Schema: public; Owner: matt; Tablespace: 
--

CREATE TABLE users (
    id bigint NOT NULL,
    name text NOT NULL
);


ALTER TABLE public.users OWNER TO matt;

SET default_tablespace = home;

--
-- Name: way_nodes; Type: TABLE; Schema: public; Owner: matt; Tablespace: home
--

CREATE TABLE way_nodes (
    id integer NOT NULL,
    node_id integer NOT NULL,
    seq integer NOT NULL
);


ALTER TABLE public.way_nodes OWNER TO matt;

--
-- Name: way_tags; Type: TABLE; Schema: public; Owner: matt; Tablespace: home
--

CREATE TABLE way_tags (
    id integer NOT NULL,
    k text NOT NULL,
    v text NOT NULL
);


ALTER TABLE public.way_tags OWNER TO matt;

--
-- Name: ways; Type: TABLE; Schema: public; Owner: matt; Tablespace: home
--

CREATE TABLE ways (
    id integer NOT NULL,
    version integer NOT NULL,
    changeset integer NOT NULL,
    tiles bytea
);


ALTER TABLE public.ways OWNER TO matt;

SET default_tablespace = '';

--
-- Name: catchup_history_pkey; Type: CONSTRAINT; Schema: public; Owner: matt; Tablespace: 
--

ALTER TABLE ONLY catchup_history
    ADD CONSTRAINT catchup_history_pkey PRIMARY KEY ("time");


--
-- Name: changeset_details_pkey; Type: CONSTRAINT; Schema: public; Owner: matt; Tablespace: 
--

ALTER TABLE ONLY changeset_details
    ADD CONSTRAINT changeset_details_pkey PRIMARY KEY (id);


--
-- Name: changesets_pkey; Type: CONSTRAINT; Schema: public; Owner: matt; Tablespace: 
--

ALTER TABLE ONLY changesets
    ADD CONSTRAINT changesets_pkey PRIMARY KEY (id);


--
-- Name: geometry_columns_pk; Type: CONSTRAINT; Schema: public; Owner: matt; Tablespace: 
--

ALTER TABLE ONLY geometry_columns
    ADD CONSTRAINT geometry_columns_pk PRIMARY KEY (f_table_catalog, f_table_schema, f_table_name, f_geometry_column);


--
-- Name: nodes_pkey; Type: CONSTRAINT; Schema: public; Owner: matt; Tablespace: 
--

ALTER TABLE ONLY nodes
    ADD CONSTRAINT nodes_pkey PRIMARY KEY (id);


--
-- Name: relations_pkey; Type: CONSTRAINT; Schema: public; Owner: matt; Tablespace: 
--

ALTER TABLE ONLY relations
    ADD CONSTRAINT relations_pkey PRIMARY KEY (id);


--
-- Name: spatial_ref_sys_pkey; Type: CONSTRAINT; Schema: public; Owner: matt; Tablespace: 
--

ALTER TABLE ONLY spatial_ref_sys
    ADD CONSTRAINT spatial_ref_sys_pkey PRIMARY KEY (srid);


--
-- Name: users_pkey; Type: CONSTRAINT; Schema: public; Owner: matt; Tablespace: 
--

ALTER TABLE ONLY users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: ways_pkey; Type: CONSTRAINT; Schema: public; Owner: matt; Tablespace: 
--

ALTER TABLE ONLY ways
    ADD CONSTRAINT ways_pkey PRIMARY KEY (id);


--
-- Name: changes_changeset_idx; Type: INDEX; Schema: public; Owner: matt; Tablespace: 
--

CREATE INDEX changes_changeset_idx ON changes USING btree (changeset);


--
-- Name: changes_tile_idx; Type: INDEX; Schema: public; Owner: matt; Tablespace: 
--

CREATE INDEX changes_tile_idx ON changes USING btree (tile);


--
-- Name: changes_time_idx; Type: INDEX; Schema: public; Owner: matt; Tablespace: 
--

CREATE INDEX changes_time_idx ON changes USING btree ("time");


--
-- Name: changeset_details_last_seen_idx; Type: INDEX; Schema: public; Owner: matt; Tablespace: 
--

CREATE INDEX changeset_details_last_seen_idx ON changeset_details USING btree (last_seen) WHERE (NOT closed);


--
-- Name: dupe_nodes_geom_idx; Type: INDEX; Schema: public; Owner: matt; Tablespace: 
--

CREATE INDEX dupe_nodes_geom_idx ON dupe_nodes USING gist (geom);


--
-- Name: dupe_nodes_tile_idx; Type: INDEX; Schema: public; Owner: matt; Tablespace: 
--

CREATE INDEX dupe_nodes_tile_idx ON dupe_nodes USING btree (tile);


--
-- Name: node_tags_idx; Type: INDEX; Schema: public; Owner: matt; Tablespace: 
--

CREATE INDEX node_tags_idx ON node_tags USING btree (id);


--
-- Name: nodes_tile_idx; Type: INDEX; Schema: public; Owner: matt; Tablespace: 
--

CREATE INDEX nodes_tile_idx ON nodes USING btree (tile);


--
-- Name: relation_members_member_idx; Type: INDEX; Schema: public; Owner: matt; Tablespace: 
--

CREATE INDEX relation_members_member_idx ON relation_members USING btree (m_id);


--
-- Name: relation_members_relation_idx; Type: INDEX; Schema: public; Owner: matt; Tablespace: 
--

CREATE INDEX relation_members_relation_idx ON relation_members USING btree (id);


--
-- Name: relation_tags_idx; Type: INDEX; Schema: public; Owner: matt; Tablespace: 
--

CREATE INDEX relation_tags_idx ON relation_tags USING btree (id);


SET default_tablespace = home;

--
-- Name: way_nodes_node_idx; Type: INDEX; Schema: public; Owner: matt; Tablespace: home
--

CREATE INDEX way_nodes_node_idx ON way_nodes USING btree (node_id);


--
-- Name: way_nodes_way_idx; Type: INDEX; Schema: public; Owner: matt; Tablespace: home
--

CREATE INDEX way_nodes_way_idx ON way_nodes USING btree (id);


SET default_tablespace = '';

--
-- Name: way_tags_idx; Type: INDEX; Schema: public; Owner: matt; Tablespace: 
--

CREATE INDEX way_tags_idx ON way_tags USING btree (id);


--
-- PostgreSQL database dump complete
--

