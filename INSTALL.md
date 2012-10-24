Setting up a database
=====================

1. Set up a regular pgsnapshot/PostGIS OSM database, see the following documents:

http://wiki.openstreetmap.org/wiki/Osmosis/Detailed_Usage#PostGIS_Tasks_.28Snapshot_Schema.29
http://wiki.openstreetmap.org/wiki/Osmosis/PostGIS_Setup

2. Run sql/owl_schema.sql in that database.

Initial data load
=================

1. Use the regular --write-pgsql Osmosis task to load inital data. See:

http://wiki.openstreetmap.org/wiki/Osmosis/Detailed_Usage#--write-pgsql_.28--wp.29

Populating the database with changes
====================================

