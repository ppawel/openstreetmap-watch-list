SELECT DISTINCT n.changeset_id
FROM nodes n
WHERE n.tstamp >= NOW() - INTERVAL '1 hour'
GROUP BY changeset_id
HAVING (NOT EXISTS (SELECT 1 FROM tiles WHERE changeset_id = n.changeset_id) OR
  MAX(n.tstamp) < (SELECT MAX(tstamp) FROM tiles WHERE changeset_id = n.changeset_id))