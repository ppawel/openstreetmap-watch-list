class ApiController < ApplicationController
  def changesets
    @x, @y, @zoom = params[:x].to_i, params[:y].to_i, params[:zoom].to_i
    @changesets = find_changesets(@x, @y, @zoom, 20)

    if params[:nogeom] == 'true'
      render :template => 'changeset/changesets_nogeom', :layout => false
    else
      #render :template => 'changeset/changesets', :layout => false
      render :json => changesets_to_geojson(@changesets, @x, @y, @zoom), :callback => params[:callback]
    end
  end

  def summary
    x, y, zoom = params[:x].to_i, params[:y].to_i, params[:zoom].to_i
    #@summary = Rails.cache.fetch("summary/#{zoom}/#{x}/#{y}", :expires_in => (30 - zoom).minutes) do
    @summary = generate_summary_tile(x, y, zoom) || {'num_changesets' => 0, 'latest_changeset' => nil}
    #end
    render :json => @summary.as_json(:except => "bbox"), :callback => params[:callback]
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
      SELECT cs.*, ST_AsGeoJSON(cst.geom) AS geojson
      FROM changeset_tiles cst
      INNER JOIN changesets cs ON (cs.id = cst.changeset_id)
      WHERE x = #{x} AND y = #{y} AND zoom = #{zoom}
      GROUP BY cs.id, cs.created_at, cs.entity_changes, cs.user_id, cst.geom
      ORDER BY cs.created_at DESC
      LIMIT #{limit}")
  end

  def find_changesets_by_range(zoom, from_x, from_y, to_x, to_y, limit)
    Changeset.find_by_sql("WITH cs_ids AS (
      SELECT DISTINCT changeset_id, MAX(tstamp) AS max_tstamp
      FROM changeset_tiles
      WHERE x >= #{from_x} AND x <= #{to_x} AND y >= #{from_y} AND y <= #{to_y} AND zoom = #{zoom}
      GROUP BY changeset_id
      ORDER BY max_tstamp DESC
      ) SELECT cs.* FROM changesets cs INNER JOIN cs_ids ON (cs.id = cs_ids.changeset_id) ORDER BY cs.created_at DESC LIMIT 30")
  end

  def find_summary_tile(x, y, zoom)
    SummaryTile.find(:first, :conditions => {:zoom => zoom, :x => x, :y => y})
  end

  # On-the-fly variant of find_summary_tile
  def generate_summary_tile(x, y, zoom)
    rows = ActiveRecord::Base.connection.execute("WITH agg AS (
        SELECT changeset_id, MAX(tstamp) AS max_tstamp
        FROM changeset_tiles
        WHERE x = #{x} AND y = #{y} AND zoom = #{zoom}
        GROUP BY changeset_id
      ) SELECT * FROM
      (SELECT COUNT(*) AS num_changesets FROM agg) a,
      (SELECT * FROM changesets WHERE id =
        (SELECT changeset_id FROM agg ORDER BY max_tstamp DESC NULLS LAST LIMIT 1)) b").to_a
    return if rows.empty?
    row = rows[0]
    summary_tile = SummaryTile.new({'num_changesets' => row['num_changesets']})
    row.delete('num_changesets')
    summary_tile.latest_changeset = Changeset.new(row)
    summary_tile
  end

  def changesets_to_geojson(changesets, x, y, zoom)
    geojson = { "type" => "FeatureCollection", "features" => []}

    changesets.each do |changeset|
      feature = { "type" => "Feature",
        "id" => "#{changeset.id}_#{x}_#{y}_#{zoom}}",
        "geometry" => JSON[changeset.geojson],
        "properties" => changeset.as_json(:except => 'bbox')
      }
      geojson['features'] << feature
    end

    geojson
  end
end
