-- Primary keys
ALTER TABLE ONLY changesets ADD CONSTRAINT pk_changesets PRIMARY KEY (id);
ALTER TABLE ONLY changeset_tiles ADD CONSTRAINT pk_changeset_tiles PRIMARY KEY (changeset_id, x, y, zoom);

ALTER TABLE ONLY nodes ADD CONSTRAINT pk_nodes PRIMARY KEY (id, version);
ALTER TABLE ONLY ways ADD CONSTRAINT pk_ways PRIMARY KEY (id, version);
ALTER TABLE ONLY relations ADD CONSTRAINT pk_relations PRIMARY KEY (id, version);
ALTER TABLE ONLY relation_members ADD CONSTRAINT pk_relation_members PRIMARY KEY (relation_id, version, sequence_id);
ALTER TABLE ONLY users ADD CONSTRAINT pk_users PRIMARY KEY (id);
