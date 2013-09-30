INSERT INTO nodes VALUES (1, 1, 't', 1, NOW(), 1, '', ST_SetSRID(ST_GeomFromText('POINT(1 1)'), 4326));
INSERT INTO nodes VALUES (2, 1, 't', 1, NOW(), 1, '', ST_SetSRID(ST_GeomFromText('POINT(2 2)'), 4326));
INSERT INTO nodes VALUES (3, 1, 't', 1, NOW(), 1, '', ST_SetSRID(ST_GeomFromText('POINT(3 3)'), 4326));
INSERT INTO ways VALUES (3, 1, 't', 1, NOW(), 1, '', ARRAY[1, 2, 3]);
INSERT INTO nodes VALUES (3, 2, 't', 1, NOW(), 2, '', ST_SetSRID(ST_GeomFromText('POINT(3.5 3.5)'), 4326));

