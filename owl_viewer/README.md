OWL VIEWER RAILS APP
====================

This is a rails app (although it's not really used in a railsy way)
which provides the main UI to OWL, viewing changes and providing RSS
feeds for areas.

## Installation

Requires

- Ruby (Ruby 1.9.x recommended)
- Rails

1) Copy `example.database.yml` in `owl_viewer/config/` to `database.yml` and configure.

2) Install application

    cd owl_viewer/
    bundle install
    rails server

3) Run rails server

    cd owl_viewer/
    rails server

## Todo

- Make more railsy, with more than one controller, etc... proper modelification of the OWL database?
- Make translatable?
