SELECT changeset_id
FROM

  (SELECT changeset_id, MAX(tstamp) AS tstamp
  FROM nodes n
  WHERE n.tstamp >= NOW() - INTERVAL '12 hour'
  GROUP BY changeset_id

  UNION

  SELECT changeset_id, MAX(tstamp) AS tstamp
  FROM ways w
  WHERE w.tstamp >= NOW() - INTERVAL '12 hour'
  GROUP BY changeset_id) x

GROUP BY changeset_id
HAVING (NOT EXISTS (SELECT 1 FROM tiles WHERE changeset_id = x.changeset_id) OR
  MAX(x.tstamp) < (SELECT MAX(tstamp) FROM tiles WHERE changeset_id = x.changeset_id))
