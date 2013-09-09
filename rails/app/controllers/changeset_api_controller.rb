require 'utils'

##
# Implements OWL API operations.
# See: http://wiki.openstreetmap.org/wiki/OWL_(OpenStreetMap_Watch_List)/API
#
class ChangesetApiController < ApplicationController
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

  def changeset_json
    @changesets = find_changeset('json')
    render :json => JSON[@changesets.map(&:generate_json)], :callback => params[:callback]
  end

  def changeset_geojson
    @changesets = find_changeset('geojson')
    render :json => changesets_to_geojson(@changesets, @x, @y, @zoom), :callback => params[:callback]
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
      FROM changeset_tiles t
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
        #{format == 'geojson' ? 'OWL_JoinTileGeometriesByChange(array_accum(t.changes), array_accum(t.geom)) AS geom_geojson,' : ''}
        #{format == 'geojson' ? 'OWL_JoinTileGeometriesByChange(array_accum(t.changes), array_accum(t.prev_geom)) AS prev_geom_geojson,' : ''}
        array_accum(((SELECT array_agg(x::box2d) FROM unnest(t.geom) x))) AS bboxes,
        cs.*,
        cs.bbox AS total_bbox,
        ARRAY(SELECT DISTINCT unnest FROM unnest(array_accum(t.changes)) ORDER by unnest) AS change_ids
      FROM changeset_tiles t
      INNER JOIN changesets cs ON (cs.id = t.changeset_id)
      WHERE x >= #{@x1} AND x <= #{@x2} AND y >= #{@y1} AND y <= #{@y2} AND zoom = #{@zoom}
        AND changeset_id IN (
          SELECT DISTINCT changeset_id
          FROM changeset_tiles
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

  def find_changeset(format)
    @id = params[:id].to_i
    changesets = ActiveRecord::Base.connection.select_all("
      SELECT cs.*,
        #{format == 'geojson' ? '(SELECT array_agg(ST_AsGeoJSON(g)) FROM unnest(t.geom) AS g) AS geom_geojson,' : ''}
        #{format == 'geojson' ? '(SELECT array_agg(ST_AsGeoJSON(g)) FROM unnest(t.prev_geom) AS g) AS prev_geom_geojson,' : ''}
        (SELECT ST_Extent(g) FROM unnest(t.geom) AS g)::text AS bboxes,
        cs.bbox::box2d::text AS total_bbox,
        (SELECT array_agg(g) FROM unnest(t.changes) AS g) AS change_ids
      FROM changeset_tiles t
      INNER JOIN changesets cs ON (cs.id = t.changeset_id)
      WHERE cs.id = #{@id}
      GROUP BY t.geom, t.prev_geom, t.changes
      ").collect {|row| Changeset.new(row)}
    load_changes(changesets)
    changesets
  end

  def generate_summary_tile
    @x, @y, @zoom = get_xyz(params)
    rows = ActiveRecord::Base.connection.select_all("WITH agg AS (
        SELECT changeset_id, MAX(tstamp) AS max_tstamp
        FROM changeset_tiles
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
        FROM changeset_tiles
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
    return if change_ids.empty?

    # Now load all the changes from the database with a single query.
    changes = {}
    for change_row in ActiveRecord::Base.connection.select_all("SELECT * FROM changes WHERE id IN
        (#{change_ids.to_a.join(',')})")
      change = Change.new(change_row)
      changes[change.id] = change
    end

    # And finally assign them back to changesets.
    for changeset in changesets
      changeset.changes = []
      changeset.change_ids.uniq.each_with_index do |change_id, index|
        if !changes.include?(change_id.to_i)
          logger.warn("Change #{change_id} not found for changeset #{changeset.id}")
          next
        end
        change = changes[change_id.to_i]
        if changeset.geom_geojson and changeset.prev_geom_geojson
          change.geom_geojson = changeset.geom_geojson[index]
          change.prev_geom_geojson = changeset.prev_geom_geojson[index]
        end
        changeset.changes << change
      end
      changeset.changes.sort! {|c1, c2| -(c1.tstamp <=> c2.tstamp)}
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
      for change in changeset.changes
        change_feature = {
          "type" => "FeatureCollection",
          "id" => "#{changeset.id}_#{change.id}",
          "properties" => {'changeset_id' => changeset.id, 'change_id' => change.id},
          "features" => []
        }
        if change.geom_geojson
          change_feature["features"] << {
            "type" => "Feature", "geometry" => JSON[change.geom_geojson],
            "properties" => {"type" => "current"}
          }
        end
        if change.prev_geom_geojson
          change_feature["features"] << {
            "type" => "Feature", "geometry" => JSON[change.prev_geom_geojson],
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
