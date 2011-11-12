CREATE TABLE users (
    id bigint NOT NULL,
    name text NOT NULL
);

ALTER TABLE ONLY users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);
