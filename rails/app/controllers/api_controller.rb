##
# Implements OWL API operations.
# See: http://wiki.openstreetmap.org/wiki/OWL_(OpenStreetMap_Watch_List)/API
#
class ApiController < ApplicationController
  include ApiHelper

  def changesets_tile_json
    @changesets = find_changesets_by_tile('json')
    render :json => JSON[@changesets.map(&:generate_json)], :callback => params[:callback]
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
    render :json => JSON[@changesets.map(&:generate_json)], :callback => params[:callback]
  end

  def changesets_tilerange_geojson
    @changesets = find_changesets_by_range('geojson')
    render :json => changesets_to_geojson(@changesets, @x, @y, @zoom), :callback => params[:callback]
  end

  def changesets_tilerange_atom
    @changesets = find_changesets_by_range('atom')
    render :template => 'api/changesets'
  end

  def summary_tile
    @summary = generate_summary_tile || {'num_changesets' => 0, 'latest_changeset' => nil}
    render :json => @summary.as_json, :callback => params[:callback]
  end

  def summary_tilerange
    @summary_list = generate_summary_tilerange || [{'num_changesets' => 0, 'latest_changeset' => nil}]
    render :json => @summary_list.as_json, :callback => params[:callback]
  end

private
  def find_changesets_by_tile(format)
    @x, @y, @zoom = get_xyz(params)
    changesets = ActiveRecord::Base.connection.select_all("
      SELECT cs.*,
        #{format == 'geojson' ? '(SELECT array_agg(ST_AsGeoJSON(g)) FROM unnest(t.geom) AS g) AS geom_geojson,' : ''}
        #{format == 'geojson' ? '(SELECT array_agg(ST_AsGeoJSON(g)) FROM unnest(t.prev_geom) AS g) AS prev_geom_geojson,' : ''}
        (SELECT ST_Extent(g) FROM unnest(t.geom) AS g)::text AS bboxes,
        cs.bbox::box2d::text AS total_bbox,
        (SELECT array_agg(g) FROM unnest(t.changes) AS g) AS change_ids
      FROM tiles t
      INNER JOIN changesets cs ON (cs.id = t.changeset_id)
      WHERE x = #{@x} AND y = #{@y} AND zoom = #{@zoom}
      #{get_timelimit_sql(params)}
      GROUP BY cs.id, t.geom, t.prev_geom, t.changes
      ORDER BY cs.created_at DESC
      #{get_limit_sql(params)}").collect {|row| Changeset.new(row)}
    load_changes(changesets)
    changesets
  end

  def find_changesets_by_range(format)
    @zoom, @x1, @y1, @x2, @y2 = get_range(params)
    changesets = ActiveRecord::Base.connection.select_all("
      SELECT
        changeset_id,
        MAX(tstamp) AS max_tstamp,
        #{format == 'geojson' ? '(SELECT array_accum((SELECT array_agg(ST_AsGeoJSON(g)) FROM unnest(t.geom) AS g))) AS geom_geojson,' : ''}
        #{format == 'geojson' ? '(SELECT array_accum((SELECT array_agg(ST_AsGeoJSON(g)) FROM unnest(t.prev_geom) AS g))) AS prev_geom_geojson,' : ''}
        array_accum(((SELECT array_agg(x::box2d) FROM unnest(t.geom) x))) AS bboxes,
        cs.*,
        cs.bbox AS total_bbox,
        array_accum(t.changes) AS change_ids
      FROM tiles t
      INNER JOIN changesets cs ON (cs.id = t.changeset_id)
      WHERE x >= #{@x1} AND x <= #{@x2} AND y >= #{@y1} AND y <= #{@y2} AND zoom = #{@zoom}
        AND changeset_id IN (
          SELECT DISTINCT changeset_id
          FROM tiles
          WHERE x >= #{@x1} AND x <= #{@x2} AND y >= #{@y1} AND y <= #{@y2} AND zoom = #{@zoom}
          #{get_timelimit_sql(params)}
          ORDER BY changeset_id DESC
          #{get_limit_sql(params)}
        )
      GROUP BY changeset_id, cs.id
      ORDER BY created_at DESC").collect {|row| Changeset.new(row)}
    load_changes(changesets)
    changesets
  end

  def generate_summary_tile
    @x, @y, @zoom = get_xyz(params)
    rows = ActiveRecord::Base.connection.select_all("WITH agg AS (
        SELECT changeset_id, MAX(tstamp) AS max_tstamp
        FROM tiles
        WHERE x = #{@x} AND y = #{@y} AND zoom = #{@zoom}
        #{get_timelimit_sql(params)}
        GROUP BY changeset_id
      ) SELECT * FROM
      (SELECT COUNT(*) AS num_changesets FROM agg) a,
      (SELECT changeset_id FROM agg ORDER BY max_tstamp DESC NULLS LAST LIMIT 1) b")
    return if rows.empty?
    row = rows[0]
    summary_tile = {'num_changesets' => row['num_changesets']}
    summary_tile['latest_changeset'] =
        ActiveRecord::Base.connection.select_all("SELECT *, NULL AS tile_bbox,
            bbox::box2d::text AS total_bbox
            FROM changesets WHERE id = #{row['changeset_id']}")[0]
    summary_tile
  end

  def generate_summary_tilerange
    @zoom, @x1, @y1, @x2, @y2 = get_range(params)
    rows = ActiveRecord::Base.connection.execute("
        SELECT x, y, COUNT(*) AS num_changesets, MAX(tstamp) AS max_tstamp, MAX(changeset_id) AS changeset_id
        FROM tiles
        INNER JOIN changesets cs ON (cs.id = changeset_id)
        WHERE x >= #{@x1} AND x <= #{@x2} AND y >= #{@y1} AND y <= #{@y2} AND zoom = #{@zoom}
        #{get_timelimit_sql(params)}
        GROUP BY x, y").to_a
    rows.to_a
  end

  def load_changes(changesets)
    return if changesets.empty?

    # Gather change ids from all changesets.
    change_ids = Set.new
    changesets.each {|changeset| change_ids.merge(changeset.change_ids)}

    # Now load all the changes from the database with a single query.
    changes = {}
    for change_row in ActiveRecord::Base.connection.select_all("SELECT * FROM changes WHERE id IN
        (#{change_ids.to_a.join(',')})")
      change = Change.new(change_row)
      changes[change.id] = change
    end

    # And finally assign them back to changesets.
    for changeset in changesets
      changeset.changes = changeset.change_ids.uniq.collect {|change_id| changes[change_id.to_i]}
    end
  end

  def changesets_to_geojson(changesets, x, y, zoom)
    geojson = { "type" => "FeatureCollection", "features" => []}
    for changeset in changesets
      changeset_geojson = {
        "type" => "FeatureCollection",
        "properties" => changeset.generate_json,
        "features" => []
      }
      changeset.change_ids.each_with_index do |change_id, index|
        change = changeset.changes.find {|change| change.id == change_id}
        change_feature = {
          "type" => "FeatureCollection",
          "id" => "#{changeset.id}_#{change.id}",
          "properties" => {'changeset_id' => changeset.id, 'change_id' => change.id},
          "features" => []
        }
        if changeset.geom_geojson[index]
          change_feature["features"] << {
            "type" => "Feature", "geometry" => JSON[changeset.geom_geojson[index]],
            "properties" => {"type" => "current"}
          }
        end
        if changeset.prev_geom_geojson[index]
          change_feature["features"] << {
            "type" => "Feature", "geometry" => JSON[changeset.prev_geom_geojson[index]],
            "properties" => {"type" => "prev"}
          }
        end
        changeset_geojson['features'] << change_feature
      end
      geojson['features'] << changeset_geojson
    end
    geojson
  end

  def pg_string_to_array(str)
    dup = str.dup
    dup[0] = '['
    dup[-1] = ']'
    dup.gsub!('NULL', 'nil')
    eval(dup)
  end
end
