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
    #@tile = find_summary_tile(params[:x].to_i, params[:y].to_i, params[:zoom].to_i)
    @tile = generate_summary_tile(params[:x].to_i, params[:y].to_i, params[:zoom].to_i)
    render :json => @tile, :callback => params[:callback]
  end

  def feed
    zoom = params[:zoom].to_i
    from_x, from_y = params[:from].split('/').map(&:to_i)
    to_x, to_y = params[:to].split('/').map(&:to_i)
    @changesets = find_changesets_by_range(zoom, from_x, from_y, to_x, to_y, 30)
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

  def find_changesets_by_range(zoom, from_x, from_y, to_x, to_y, limit)
    subtiles_per_tile = 2**16 / 2**zoom
    Changeset.find_by_sql("
      SELECT DISTINCT cs.*
      FROM changeset_tiles cst
      INNER JOIN changesets cs ON (cs.id = cst.changeset_id)
      WHERE zoom = 16
            AND x >= #{from_x * subtiles_per_tile} AND x < #{(to_x + 1) * subtiles_per_tile}
            AND y >= #{from_y * subtiles_per_tile} AND y < #{(to_y + 1) * subtiles_per_tile}
      ORDER BY cs.created_at DESC
      LIMIT #{limit}
      ")
  end

  def find_summary_tile(x, y, zoom)
    SummaryTile.find(:first, :conditions => {:zoom => zoom, :x => x, :y => y})
  end

  # On-the-fly variant of find_summary_tile
  def generate_summary_tile(x, y, zoom)
    subtiles_per_tile = 2**16 / 2**zoom
    SummaryTile.find_by_sql("SELECT COUNT(DISTINCT changeset_id) AS num_changesets
          FROM changeset_tiles
          WHERE zoom = 16
            AND x >= #{x * subtiles_per_tile} AND x < #{(x + 1) * subtiles_per_tile}
            AND y >= #{y * subtiles_per_tile} AND y < #{(y + 1) * subtiles_per_tile}
          ")[0]
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
