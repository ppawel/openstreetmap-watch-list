DROP FUNCTION IF EXISTS OWL_UpdateChangesetGeom(bigint);
DROP FUNCTION IF EXISTS OWL_UpdateChangesetChangeCount(bigint);
DROP FUNCTION IF EXISTS OWL_UpdateAllChangesetsGeom();
DROP FUNCTION IF EXISTS OWL_UpdateAllChangesetsChangeCount();

CREATE FUNCTION OWL_UpdateChangesetGeom(bigint) RETURNS void AS $$
DECLARE
  changeset_geom geography;
BEGIN

changeset_geom := (
  SELECT ST_Collect(DISTINCT g.geom)::geography
  FROM
  (
    SELECT current_geom::geometry AS geom FROM changes WHERE changeset_id = $1
    UNION
    SELECT new_geom::geometry AS geom FROM changes WHERE changeset_id = $1
  ) g);

UPDATE changesets SET geom = changeset_geom WHERE id = $1;

END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION OWL_UpdateChangesetChangeCount(bigint) RETURNS void AS $$
  UPDATE
    changesets cs
  SET num_changes = (SELECT COUNT(*) FROM changes c WHERE c.changeset_id = cs.id)
  WHERE cs.id = $1;
$$ LANGUAGE SQL;

CREATE FUNCTION OWL_UpdateAllChangesetsGeom() RETURNS void AS $$
DECLARE
  changeset_id bigint;
BEGIN
FOR changeset_id IN SELECT id FROM changesets LOOP
  --RAISE NOTICE '% Changeset %', clock_timestamp(), changeset_id;
  PERFORM OWL_UpdateChangesetGeom(changeset_id);
END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION OWL_UpdateAllChangesetsChangeCount() RETURNS void AS $$
DECLARE
  changeset_id bigint;
BEGIN
FOR changeset_id IN SELECT id FROM changesets LOOP
  --RAISE NOTICE '% Changeset %', clock_timestamp(), changeset_id;
  PERFORM OWL_UpdateChangesetChangeCount(changeset_id);
END LOOP;
END;
$$ LANGUAGE plpgsql;
