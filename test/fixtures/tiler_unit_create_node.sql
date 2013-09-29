INSERT INTO nodes VALUES (1, 1, 't', 1, NOW(), 1, '', ST_SetSRID(ST_GeomFromText('POINT(3 4)'), 4326));
INSERT INTO nodes VALUES (2, 1, 't', 1, NOW(), 1, 'a=>1', ST_SetSRID(ST_GeomFromText('POINT(1 2)'), 4326));
