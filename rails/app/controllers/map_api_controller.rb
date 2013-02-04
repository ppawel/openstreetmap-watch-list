require 'utils'

##
# Implements OWL API operations.
# See: http://wiki.openstreetmap.org/wiki/OWL_(OpenStreetMap_Watch_List)/API
#
class MapApiController < ApplicationController
  include ApiHelper

  def kothic
    @x, @y, @zoom = get_xyz(params)
    tile_bbox = tile2bbox(@x, @y, @zoom)
    p tile_bbox
    tiles = ActiveRecord::Base.connection.select_all("
      WITH tile_bbox AS (
        SELECT ST_Transform(ST_SetSRID('LINESTRING(#{tile_bbox[0]} #{tile_bbox[1]},
          #{tile_bbox[2]} #{tile_bbox[3]})'::geometry, 4326), 900913)::box2d g
      )
      SELECT ST_AsGeoJSON(ST_TransScale(ST_Transform(geom, 900913),
        (SELECT -ST_XMax(g) FROM tile_bbox),
        (SELECT -ST_YMax(g) FROM tile_bbox),
        (SELECT 10000 / (ST_XMin(g) - ST_XMax(g)) FROM tile_bbox),
        (SELECT 10000 / (ST_YMin(g) - ST_YMax(g)) FROM tile_bbox)

         ), 0

      ) AS geojson,
        w.tags
      FROM way_tiles t
      INNER JOIN ways w ON (w.id = t.way_id AND w.version = t.version)
      WHERE x >= #{@x * (2 ** (16 - @zoom))} AND y >= #{@y * (2 ** (16 - @zoom))} AND
        x <= #{(@x + 1) * (2 ** (16 - @zoom))} AND y <= #{(@y + 1) * (2 ** (16 - @zoom))}

      ").to_a

    geojson = []

    for tile in tiles
      kothic_tile = JSON[tile['geojson']]
      kothic_tile['properties'] = eval("{#{tile['tags']}}")
      geojson << kothic_tile
    end
    text = "onKothicDataResponse({\"features\": #{JSON[geojson].as_json}, \"bbox\":#{tile_bbox}, \"granularity\": 10000 },
      #{@zoom}, #{@x}, #{@y})"
    render :js => text
  end

end
