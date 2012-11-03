class ApiController < ApplicationController
  def changesets
    @changesets = find_changesets(params[:x].to_i, params[:y].to_i, params[:zoom].to_i, 20)

    if params[:nogeom] == 'true'
      render :template => 'changeset/changesets_nogeom', :layout => false
    else
      #render :template => 'changeset/changesets', :layout => false
      render :json => changesets_to_geojson(@changesets), :callback => params[:callback]
    end
  end

  def summary
    @tile = find_summary_tile(params[:x].to_i, params[:y].to_i, params[:zoom].to_i)
    render :json => @tile, :callback => params[:callback]
  end

private
  def find_changesets(x, y, zoom, limit)
    Changeset.find_by_sql("
      SELECT cs.id, cs.created_at, cs.num_changes, cs.user_id, ST_AsGeoJSON(ST_Union(cst.geom::geometry)) AS geojson
      FROM changeset_tiles cst
      INNER JOIN changesets cs ON (cs.id = cst.changeset_id)
      WHERE zoom = #{zoom} AND x = #{x} AND y = #{y}
      GROUP BY cs.id, cs.created_at, cs.num_changes, cs.user_id
      ORDER BY cs.created_at DESC
      LIMIT #{limit}
      ")
  end

  def find_summary_tile(x, y, zoom)
    SummaryTile.find(:first, :conditions => {:zoom => zoom, :x => x, :y => y})
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
end
