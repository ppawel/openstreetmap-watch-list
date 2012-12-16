psql -d owl -c "\copy (SELECT * FROM OWL_GenerateChanges($1)) to stdout"
