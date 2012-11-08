DROP FUNCTION IF EXISTS OWL_UpdateChangeset(bigint);

CREATE FUNCTION OWL_UpdateChangeset(bigint) RETURNS void AS $$
DECLARE
  change_count int;
BEGIN
  change_count := (SELECT COUNT(*) FROM changes WHERE changeset_id = $1);
  UPDATE changesets cs SET num_changes = change_count WHERE cs.id = $1;
END;
$$ LANGUAGE plpgsql;
