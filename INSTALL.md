Setting up the database
=======================

1. Set up a PostgreSQL database with the PostGIS extension (see [PostGIS setup](http://wiki.openstreetmap.org/wiki/Osmosis/PostGIS_Setup) document for help with that).
2. Run the `sql/pgsnapshot_schema_0.6.sql` script in that database.
3. Run the `sql/pgsnapshot_schema_0.6_linestring.sql` script in that database.
4. Run the `sql/owl_schema.sql` script in that database.

Initial data import
===================

If you don't want to process all OSM data changes "since forever" that will build up your database from scratch, you can start from any point in time. In order to do that, you need to do an initial data import.

OWL database schema is compatible with the Osmosis pgsnapshot schema so you can/should use the `--write-pgsql` [Osmosis task](http://wiki.openstreetmap.org/wiki/Osmosis/Detailed_Usage#--write-pgsql_.28--wp.29) to import data.

Installing the OWL Osmosis plugin
=================================

OWL plugin for Osmosis is needed for the `--write-owldb-change` task which populates OWL tables with data.

To install the plugin just drop the JAR file from the `osmosis-plugin` directory to the `lib` directory in your Osmosis installation (e.g. `/usr/share/osmosis`).

If you want, you can also build the plugin from the source]():

1. Clone [the source code](https://github.com/ppawel/osmosis/tree/owldb-plugin).
2. Type `ant build`.
3. In the `package` directory you should now have a full Osmosis distribution ready to be used (the plugin itself is in the `package/lib/default` directory).

Populating the database with changes
====================================

In order to start populating OWL tables, you need to process OsmChange files against your database.

The easiest way to do this is to set up the Osmosis interval replication.

First, [initialize replication directory](http://wiki.openstreetmap.org/wiki/Osmosis/Detailed_Usage#--read-replication-interval-init_.28--rrii.29).

Then, set up (e.g. in crontab) the replication pipeline:

    osmosis --read-replication-interval workingDirectory=<dir> --tee-change  --write-owldb-change authFile=<authFile> --write-pgsql-change authFile=<authFile>

This commands does couple of things:
* Downloads OsmChange file for a specific replication interval (minute/hour/day) - according to the configuration in the `configuration.txt` file.
* The change stream goes to the OWL Osmosis plugin which populates OWL tables and then applies changes to regular data tables (same as with the `--write-pgsql-change` task).
