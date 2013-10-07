INSERT INTO nodes VALUES (1, 1, 't', 1, '2013-03-03 18:00:00', 1, '', ST_SetSRID(ST_GeomFromText('POINT(1 1)'), 4326));
INSERT INTO nodes VALUES (2, 1, 't', 1, '2013-03-03 18:00:00', 1, '', ST_SetSRID(ST_GeomFromText('POINT(2 2)'), 4326));
INSERT INTO nodes VALUES (3, 1, 't', 1, '2013-03-03 18:00:00', 1, '', ST_SetSRID(ST_GeomFromText('POINT(3 3)'), 4326));
INSERT INTO ways VALUES (3, 1, 't', 1, '2013-03-03 18:00:00', 1, '', ARRAY[1, 2, 3]);

INSERT INTO nodes VALUES (3, 2, 't', 1, '2013-03-03 19:00:00', 2, 'some=>tag', ST_SetSRID(ST_GeomFromText('POINT(3 3)'), 4326));

INSERT INTO nodes VALUES (10, 1, 't', 1, '2013-03-03 20:00:00', 3, '', ST_SetSRID(ST_GeomFromText('POINT(18.6023903 49.8778083)'), 4326));
INSERT INTO nodes VALUES (11, 1, 't', 1, '2013-03-03 20:00:01', 3, '', ST_SetSRID(ST_GeomFromText('POINT(18.6024903 49.8778083)'), 4326));
INSERT INTO nodes VALUES (12, 1, 't', 1, '2013-03-03 20:00:05', 3, '', ST_SetSRID(ST_GeomFromText('POINT(18.6025903 49.8778083)'), 4326));

INSERT INTO ways VALUES (5, 1, 't', 1, '2013-03-03 20:00:10', 3, '', ARRAY[10, 11, 12]);

INSERT INTO nodes VALUES (11, 2, 't', 1, '2013-03-03 20:00:21', 3, '', ST_SetSRID(ST_GeomFromText('POINT(18.6024903 49.8779083)'), 4326));
