Setting up a database
=====================

1. Set up a regular pgsnapshot/PostGIS OSM database, see the following documents:
 * [PostGIS setup](http://wiki.openstreetmap.org/wiki/Osmosis/PostGIS_Setup)
 * [Setting up pgsnapshot schema](http://wiki.openstreetmap.org/wiki/Osmosis/Detailed_Usage#PostGIS_Tasks_.28Snapshot_Schema.29)
2. Run the `sql/owl_schema.sql` script in that database.

Initial data load
=================

1. Use the `--write-pgsql` [Osmosis task](http://wiki.openstreetmap.org/wiki/Osmosis/Detailed_Usage#--write-pgsql_.28--wp.29) to load inital data.

Populating the database with changes
====================================

In order to start populating OWL tables, you need to process OsmChange files against your database. The easiest way to do this is to set up the Osmosis interval replication.

First, [initialize replication directory](http://wiki.openstreetmap.org/wiki/Osmosis/Detailed_Usage#--read-replication-interval-init_.28--rrii.29).

Then, setup (e.g. in crontab) the replication pipeline:

    osmosis --read-replication-interval workingDirectory=<dir> --tee-change
    --write-changedb-change authFile=<authFile> --write-pgsql-change authFile=<authFile>

This commands does couple of things:
* Downloads OsmChange file for a specific replication interval (minute/hour/day) - according to the configuration in `configuration.txt`.
* First, the change stream goes to the OWL Osmosis plugin - it populates change tables.
* Then the stream goes to the regular `--write-pgsql-change` task that makes modifications in the data tables.
