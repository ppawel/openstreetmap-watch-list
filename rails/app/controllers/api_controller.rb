##
# Implements OWL API operations.
# See: http://wiki.openstreetmap.org/wiki/OWL_(OpenStreetMap_Watch_List)/API
#
class ApiController < ApplicationController
  include ApiHelper

  def changesets_tile_json
    @changesets = find_changesets_by_tile('json')
    render :json => JSON[@changesets], :callback => params[:callback]
  end

  def changesets_tile_geojson
    @changesets = find_changesets_by_tile('geojson')
    render :json => changesets_to_geojson(@changesets, @x, @y, @zoom), :callback => params[:callback]
  end

  def changesets_tile_atom
    @changesets = find_changesets_by_tile('atom')
    render :template => 'api/changesets'
  end

  def changesets_tilerange_json
    @changesets = find_changesets_by_range('json')
    render :json => JSON[@changesets], :callback => params[:callback]
  end

  def changesets_tilerange_geojson
    @changesets = find_changesets_by_range('geojson')
    render :json => changesets_to_geojson(@changesets, @x, @y, @zoom), :callback => params[:callback]
  end

  def changesets_tilerange_atom
    @changesets = find_changesets_by_range('atom')
    render :template => 'api/changesets'
  end

  def summary
    @x, @y, @zoom = get_xyz(params)
    @summary = generate_summary_tile(@x, @y, @zoom) || {'num_changesets' => 0, 'latest_changeset' => nil}
    render :json => @summary.as_json(:except => "bbox"), :callback => params[:callback]
  end

private
  def find_changesets_by_tile(format)
    @x, @y, @zoom = get_xyz(params)
    rows = Changeset.find_by_sql("
      SELECT cs.* #{format == 'geojson' ? ', ST_AsGeoJSON(cst.geom) AS geojson' : ''}, cst.geom::box2d::text AS tile_bbox
      FROM changeset_tiles cst
      INNER JOIN changesets cs ON (cs.id = cst.changeset_id)
      WHERE x = #{@x} AND y = #{@y} AND zoom = #{@zoom}
      GROUP BY cs.id, cs.created_at, cs.entity_changes, cs.user_id, cst.geom
      ORDER BY cs.created_at DESC
      LIMIT #{get_limit(params)}")
    ActiveRecord::Associations::Preloader.new(rows, [:user]).run
    rows
  end

  def find_changesets_by_range(format)
    @zoom, @x1, @y1, @x2, @y2 = get_range(params)
    rows = Changeset.find_by_sql("WITH cs_ids AS (
      SELECT DISTINCT changeset_id, MAX(tstamp) AS max_tstamp
      FROM changeset_tiles
      WHERE x >= #{@x1} AND x <= #{@x2} AND y >= #{@y1} AND y <= #{@y2} AND zoom = #{@zoom}
      GROUP BY changeset_id
      ORDER BY max_tstamp DESC
      ) SELECT cs.* FROM changesets cs INNER JOIN cs_ids ON (cs.id = cs_ids.changeset_id) ORDER BY cs.created_at DESC LIMIT 30")
    ActiveRecord::Associations::Preloader.new(rows, [:user]).run
    rows
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
      (SELECT changeset_id FROM agg ORDER BY max_tstamp DESC NULLS LAST LIMIT 1) b").to_a
    return if rows.empty?
    row = rows[0]
    summary_tile = SummaryTile.new({'num_changesets' => row['num_changesets']})
    row.delete('num_changesets')
    summary_tile.latest_changeset =
        Changeset.find_by_sql("SELECT *, NULL AS tile_bbox FROM changesets WHERE id = #{row['changeset_id']}")[0]
    summary_tile
  end

  def changesets_to_geojson(changesets, x, y, zoom)
    geojson = { "type" => "FeatureCollection", "features" => []}
    changesets.each do |changeset|
      feature = { "type" => "Feature",
        "id" => "#{changeset.id}_#{x}_#{y}_#{zoom}}",
        "geometry" => changeset.geojson ? JSON[changeset.geojson] : nil,
        "properties" => changeset.as_json(:except => 'bbox')
      }
      geojson['features'] << feature
    end
    geojson
  end
end
