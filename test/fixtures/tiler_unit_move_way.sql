INSERT INTO nodes VALUES (1, 1, 't', 1, NOW(), 1, '', ST_SetSRID(ST_GeomFromText('POINT(0.001 0.001)'), 4326));
INSERT INTO nodes VALUES (2, 1, 't', 1, NOW(), 1, '', ST_SetSRID(ST_GeomFromText('POINT(0.002 0.002)'), 4326));
INSERT INTO nodes VALUES (3, 1, 't', 1, NOW(), 1, '', ST_SetSRID(ST_GeomFromText('POINT(0.003 0.003)'), 4326));
INSERT INTO ways VALUES (3, 1, 't', 1, NOW(), 1, '', ARRAY[1, 2, 3]);
INSERT INTO nodes VALUES (3, 2, 't', 1, NOW(), 2, '', ST_SetSRID(ST_GeomFromText('POINT(0.0035 0.0035)'), 4326));

INSERT INTO nodes VALUES (4, 1, 't', 1, NOW(), 3, '', ST_SetSRID(ST_GeomFromText('POINT(0.001 0.001)'), 4326));
INSERT INTO nodes VALUES (5, 1, 't', 1, NOW(), 3, '', ST_SetSRID(ST_GeomFromText('POINT(0.002 0.002)'), 4326));
INSERT INTO nodes VALUES (6, 1, 't', 1, NOW(), 3, '', ST_SetSRID(ST_GeomFromText('POINT(0.003 0.003)'), 4326));
INSERT INTO ways VALUES (4, 1, 't', 1, NOW(), 3, '', ARRAY[4, 5, 6]);
INSERT INTO nodes VALUES (5, 2, 't', 1, NOW(), 3, '', ST_SetSRID(ST_GeomFromText('POINT(0.0035 0.0035)'), 4326));
