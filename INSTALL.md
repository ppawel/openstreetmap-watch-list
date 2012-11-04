Setting up the database
=======================

Installation instructions for PostgreSQL 9.1, for equivalent 8.x procedures
refer to http://wiki.openstreetmap.org/wiki/Osmosis/PostGIS_Setup.

1) Set up PostGIS database

    # Assuming a database owl here, can be any other database name.
    createdb owl
    createlang plpgsql owl
    psql -f /path/to/pgsql/share/contrib/postgis-2.0/postgis.sql owl
    psql -f /path/to/pgsql/share/contrib/postgis-2.0/spatial_ref_sys.sql owl

2) Create hstore extension

    psql -c "CREATE EXTENSION hstore;" owl

3) Set up pg snapshot schema

    psql -f sql/pgsnapshot_schema_0.6.sql owl
    psql -f sql/pgsnapshot_schema_0.6_linestring.sql owl

4) Install OWL schema

    psql -f sql/owl_schema.sql owl
    psql -f sql/owl_functions.sql owl

Install Osmosis
===============

For now we're using a modified version of Osmosis, this should just be an Osmosis plugin in the future.

    git clone -b owldb-plugin https://github.com/ppawel/osmosis.git
    cd osmosis/
    ant build
    # Copy resulting build to a path of your convenience

Initial data import
===================

*For development*

For development it's usually sufficient to import a single osc diff file. For instance:

    curl -o 757.osc.gz http://planet.osm.org/replication/minute/000/069/757.osc.gz
    osmosis --read-xml-change 757.osc --lpc --write-owldb-change database=owl user=postgres

*From Planet file*

You can save time by not doing a full history import and use the lighter Planet file without historic changesets from [planet.osm.org](http://planet.osm.org/).

The OWL database schema is compatible with the Osmosis pgsnapshot schema so you can use the [Osmosis `--write-pgsql` task](http://wiki.openstreetmap.org/wiki/Osmosis/Detailed_Usage#--write-pgsql_.28--wp.29) to import OSM data.

    # Assuming a database owl and a user postgres
    curl -o planet.osm.bz2 http://planet.osm.org/planet/planet-latest.osm.bz2
    bunzip2 planet.osm.bz2
    osmosis --read-xml planet.osm --write-pgsql database=owl user=postgres

*From full history Planet file*

Technically it would be possible to avoid processing osc diffs by using a full history diff. However, this is not
supported right now (and probably never will be since it is not really too practical - it would take a Very Long Time to
process full history planet).

Populating the database with changes
====================================

In order to start populating OWL tables, you need to process OsmChange files against your database.

The easiest way to do this is to set up the Osmosis interval replication.

1) [Initialize replication directory](http://wiki.openstreetmap.org/wiki/Osmosis/Detailed_Usage#--read-replication-interval-init_.28--rrii.29).

2) Set up (e.g. in crontab) the replication pipeline:

    # Make sure to use the OWL specific osmosis version built above
    osmosis \
    --read-replication-interval workingDirectory=replication/ \
    --write-pgsql-change database=owl user=postgres

This command:

- downloads OsmChange file for a specific replication interval (minute/hour/day) - according to the configuration in the `configuration.txt` file.
- populates OWL tables and then applies changes to regular data tables (same as `--write-pgsql-change` task).

Generating geometry tiles
=========================

OWL serves changeset geometries using tiles - similar to regular map tiles (images). The tiles need to be generated
after data is imported into the database.

Generating tiles is done using the `owl_tiler.rb` script. To generate tiles for zoom level 16:

    cd tiler
    ./owl_tiler.rb --geometry-tiles 16

To see the list of possible options and usage instructions, execute the script without any options, like so:

    cd tiler
    ./owl_tiler.rb

Set up Rails app
================

See `rails/README.md`.
