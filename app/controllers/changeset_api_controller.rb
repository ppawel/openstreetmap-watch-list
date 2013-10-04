require 'utils'
require 'changeset_tiler'

##
# Implements OWL API operations.
# See: http://wiki.openstreetmap.org/wiki/OWL/API
#
class ChangesetApiController < ApplicationController
  include ApiHelper

  def changesets_tile_json
    @changesets = find_changesets_by_tile
    render :json => JSON[@changesets.map(&:generate_json)], :callback => params[:callback]
  end

  def changesets_tile_atom
    @changesets = find_changesets_by_tile
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
  def find_changesets_by_tile
    @x, @y, @zoom = get_xyz(params)
    changesets = ActiveRecord::Base.connection.raw_connection().exec("
      SELECT
        changeset_id,
        t.tstamp AS max_tstamp,
        cs.*,
        cs.bbox AS total_bbox,
        t.changes::change[],
        (SELECT array_agg(tags) FROM unnest(t.changes)) AS change_tags,
        (SELECT array_agg(prev_tags) FROM unnest(t.changes)) AS change_prev_tags,
        (SELECT array_agg(ST_AsGeoJSON(geom)) FROM unnest(t.changes)) AS geojson,
        (SELECT array_agg(ST_AsGeoJSON(prev_geom)) FROM unnest(t.changes)) AS prev_geojson
      FROM changeset_tiles t
      INNER JOIN changesets cs ON (cs.id = t.changeset_id)
      WHERE x = #{@x} AND y = #{@y} AND zoom = #{@zoom}
        AND changeset_id IN (
          SELECT DISTINCT changeset_id
          FROM changeset_tiles
          WHERE x = #{@x} AND y = #{@y} AND zoom = #{@zoom}
          #{get_timelimit_sql(params)}
          ORDER BY changeset_id DESC
          #{get_limit_sql(params)}
        )
      ORDER BY created_at DESC").collect {|row| Changeset.new(row)}
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

  def pg_string_to_array(str)
    dup = str.dup
    dup[0] = '['
    dup[-1] = ']'
    dup.gsub!('NULL', 'nil')
    eval(dup)
  end
end
