class ChangesetController < ApplicationController
  def dailymap
    @title = "Map of changes over the past day"
    common_map(" AND age(time) < '1 day'", 0.5)
  end

  def weeklymap
    @title = "Map of changes over the past week"
    common_map(" AND age(time) < '1 week'", 0.15)
  end

  def map
    @title = "Map of all changes"
    common_map("", 0.1)
  end

private
  def find_changesets_by_bbox(bbox)
    Changeset.find(:all,
      :select => "changesets.*, users.id AS user_id, users.name, ST_AsGeoJSON(ST_Intersection(ST_SetSRID(Box2D(ST_GeomFromText('LINESTRING(#{bbox[0]} #{bbox[1]}, #{bbox[2]} #{bbox[3]})')), 4326), geom)) AS geojson",
      :conditions => "ST_Intersects(ST_SetSRID(Box2D(ST_GeomFromText('LINESTRING(#{bbox[0]} #{bbox[1]}, #{bbox[2]} #{bbox[3]})')), 4326), geom)",
      :joins => :user,
      :limit => 100,
      :order => 'created_at DESC')
  end

  def common_map(where_time, max_area)
    unless params['bbox'].nil?
      bbox = params['bbox'].split(/,/).map { |x| x.to_f }
      area = (bbox[2] - bbox[0]) * (bbox[3] - bbox[1])

      if (area < max_area)
        @changesets = find_changesets_by_bbox(bbox)
      end
    end
    render :layout => 'with_map'
  end
end
