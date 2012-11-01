class ChangesetController < ApplicationController
  def changesets
    @changesets = find_changesets_by_tile(params[:x].to_i, params[:y].to_i, params[:zoom].to_i, 20)

    if params[:nogeom] == 'true'
      render :template => 'changeset/changesets_nogeom', :layout => false
    else
      #render :template => 'changeset/changesets', :layout => false
      render :json => changesets_to_geojson(@changesets), :callback => params[:callback]
    end
  end

private
  def find_changesets_by_bbox(bbox, limit)
    Changeset.find(:all,
      :select => "changesets.*, users.id AS user_id, users.name, ST_AsGeoJSON(ST_Intersection(ST_SetSRID('BOX(#{bbox[0]} #{bbox[1]}, #{bbox[2]} #{bbox[3]})'::box2d, 4326), geom)) AS geojson",
      :conditions => "ST_Intersects(ST_SetSRID('BOX(#{bbox[0]} #{bbox[1]}, #{bbox[2]} #{bbox[3]})'::box2d, 4326), geom)",
      :joins => :user,
      :limit => limit,
      :order => 'created_at DESC')
  end

  def find_changesets_by_tile(x, y, zoom, limit)
    Changeset.find_by_sql("
      SELECT cs.*, ST_AsGeoJSON(ST_Union(cst.geom::geometry)) AS geojson
      FROM changeset_tiles cst
      INNER JOIN changesets cs ON (cs.id = cst.changeset_id)
      WHERE zoom = #{zoom} AND tile_x = #{x} AND tile_y = #{y}
      GROUP BY cs.id
      ORDER BY cs.created_at
      LIMIT #{limit}
      ")
  end

  def changesets_to_geojson(changesets)
    geojson = { "type" => "FeatureCollection", "features" => []}

    changesets.each do |changeset|
      feature = { "type" => "Feature",
        "id" => "#{changeset.id}_#{rand(666666)}",
        "geometry" => JSON[changeset.geojson],
        "properties" => {
          "changeset_id" => changeset.id,
          "created_at" => changeset.created_at,
          "user_id" => changeset.user.id,
          "user_name" => changeset.user.name,
          "num_changes" => changeset.num_changes
        }
      }

      geojson['features'] << feature
    end

    geojson
  end

  def xyz_to_bbox(x, y, z)
    tl = xyz_to_latlon(x, y, z)
    br = xyz_to_latlon(x + 1, y + 1, z)
    [tl[0], tl[1], br[0], br[1]]
  end

  def xyz_to_latlon(x, y, z)
    n = 2 ** z
    lon_deg = x.to_f / n * 360.0 - 180.0
    lat_rad = Math.atan(Math.sinh(Math::PI * (1 - 2 * y.to_f / n)))
    lat_deg = lat_rad * 180.0 / Math::PI
    return lon_deg, lat_deg
  end
end
