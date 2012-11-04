OWL API
=======

`<api_url>` in this document refers to a base URL pointing at the OWL Rails application.

Changesets
----------

`<api_url>/changesets/zoom/x/y` - responds with a list of changesets for the tile together with their geometry formatted
as GeoJSON. `zoom`, `x` and `y` parameters should follow the standard slippy map numbering scheme.

Example:
TBD

Summary tiles
-------------

`<api_url>/summary/zoom/x/y` - responds with a summary of changesets for the tile formatted as JSON.

Example:
TBD
