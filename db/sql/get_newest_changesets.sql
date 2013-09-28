SELECT DISTINCT changeset_id
FROM nodes WHERE tstamp >= (SELECT MAX(tstamp) FROM tiles)
UNION
SELECT DISTINCT changeset_id
FROM ways WHERE tstamp >= (SELECT MAX(tstamp) FROM tiles)
