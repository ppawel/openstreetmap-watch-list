DROP FUNCTION IF EXISTS OWL_UpdateChangesetGeom(bigint);
DROP FUNCTION IF EXISTS OWL_UpdateChangesetChangeCount(bigint);
DROP FUNCTION IF EXISTS OWL_UpdateAllChangesetsGeom();
DROP FUNCTION IF EXISTS OWL_UpdateAllChangesetsChangeCount();
DROP FUNCTION IF EXISTS OWL_GenerateTiles(int, int);
DROP FUNCTION IF EXISTS OWL_GenerateChangesetTiles(bigint, int);

DROP FUNCTION IF EXISTS OWL_LatLonToTileXY(int, geometry);
DROP FUNCTION IF EXISTS OWL_TileXYToLatLon(int, int, int);
DROP FUNCTION IF EXISTS OWL_TileXYToBOX(int, int, int);

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

CREATE FUNCTION OWL_LatLonToTileXY(int, geometry) RETURNS record AS $$
  SELECT
    (POW(2, $1) * ((ST_X($2) + 180) / 360))::int AS tile_x,
    (POW(2, $1) * ((ST_Y(ST_Transform($2, 900913)) + 20037508.34) / (20037508.34 * 2)))::int AS tile_y;
$$ LANGUAGE SQL;


CREATE FUNCTION OWL_TileXYToLatLon(int, int, int) RETURNS geometry AS $$
  SELECT ST_MakePoint(
    $2 / POW(2, $1) * 360 - 180,
    ST_Y(ST_Transform(ST_SetSRID(ST_MakePoint(0, $3 / POW(2, $1) * 20037508.34 * 2 - 20037508.34), 900913), 4326)));
$$ LANGUAGE SQL;

CREATE FUNCTION OWL_TileXYToBOX(int, int, int) RETURNS box2d AS $$
  SELECT ST_MakeBox2D(
    ST_MakePoint(ST_X(OWL_TileXYToLatLon($1, $2, $3)), ST_Y(OWL_TileXYToLatLon($1, $2 + 1, $3 + 1))),
    ST_MakePoint(ST_X(OWL_TileXYToLatLon($1, $2 + 1, $3 + 1)), ST_Y(OWL_TileXYToLatLon($1, $2, $3)))
    );
$$ LANGUAGE SQL;

CREATE FUNCTION OWL_GenerateChangesetTiles(bigint, int) RETURNS int AS $$
DECLARE
  changeset_geom geometry;
  tile_geom geometry;
  tile_xy_topleft record;
  tile_xy_bottomright record;
  tile_box box2d;
  tile_latlon1 geometry;
  tile_latlon2 geometry;
  i int;
  j int;
  count int;

BEGIN
  DELETE FROM changeset_tiles WHERE changeset_id = $1 and zoom = $2;

  count := 0;
  changeset_geom := (SELECT geom::geometry FROM changesets WHERE id = $1);

  IF changeset_geom IS NULL OR ST_IsEmpty(changeset_geom) THEN
    RETURN -1;
  END IF;

  --RAISE NOTICE '%', ST_astext(changeset_geom);

  tile_xy_topleft := OWL_LatLonToTileXY($2,
    ST_SetSRID(ST_MakePoint(ST_XMin(changeset_geom), ST_YMin(changeset_geom)), 4326));

  tile_xy_bottomright := OWL_LatLonToTileXY($2,
    ST_SetSRID(ST_MakePoint(ST_XMax(changeset_geom), ST_YMax(changeset_geom)), 4326));

  FOR i IN tile_xy_topleft.tile_x..tile_xy_bottomright.tile_x LOOP
    FOR j IN tile_xy_topleft.tile_y..tile_xy_bottomright.tile_y LOOP
      tile_box := OWL_TileXYToBOX($2, i, j);
      --RAISE NOTICE 'Processing tile % % % ...', i, j, tile_box;
      tile_geom := ST_Intersection(ST_SetSRID(tile_box, 4326), changeset_geom);

      IF NOT ST_IsEmpty(tile_geom) THEN
        --RAISE NOTICE 'Got ourselves a tile geometry';
        count := count + 1;

        INSERT INTO changeset_tiles (changeset_id, zoom, tile_x, tile_y, geom)
          VALUES ($1, $2, i, j, tile_geom);
      END IF;
    END LOOP;
  END LOOP;

  RETURN count;
END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION OWL_GenerateTiles(int, int) RETURNS void AS $$
DECLARE
  changeset_id bigint;
BEGIN
FOR changeset_id IN SELECT id FROM changesets ORDER BY id LIMIT $2 LOOP
  --RAISE NOTICE '% Changeset %', clock_timestamp(), changeset_id;
  PERFORM OWL_GenerateChangesetTiles(changeset_id, $1);
END LOOP;
END;
$$ LANGUAGE plpgsql;
