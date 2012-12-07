SELECT changeset_id FROM (
SELECT DISTINCT n.changeset_id FROM nodes n INNER JOIN nodes n2 ON (n2.id = n.id AND n2.version = n.version - 1)
UNION
SELECT DISTINCT w.changeset_id FROM ways w INNER JOIN ways w2 ON (w2.id = w.id AND w2.version = w.version - 1)
) x ORDER BY changeset_id DESC;
