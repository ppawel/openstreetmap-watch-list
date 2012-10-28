class ChangesetController < ApplicationController
  def changesets
    bbox = params['bbox'].split(/,/).map { |x| x.to_f }
    area = (bbox[2] - bbox[0]) * (bbox[3] - bbox[1])

    #if (area < max_area)
      @changesets = find_changesets_by_bbox(bbox)
    #end

    render :template => "changeset/changesets.#{params[:format]}", :layout => false
  end

  def dailymap
    @title = "owl_viewer | Map of changes over the past day"
  end

  def weeklymap
    @title = "owl_viewer | Map of changes over the past week"
  end

  def map
    @title = "owl_viewer | Map of all changes"
  end

private
  def find_changesets_by_bbox(bbox)
    Changeset.find(:all,
      :select => "changesets.*, users.id AS user_id, users.name, ST_AsGeoJSON(ST_Intersection(ST_SetSRID('BOX(#{bbox[0]} #{bbox[1]}, #{bbox[2]} #{bbox[3]})'::box2d, 4326), geom)) AS geojson",
      :conditions => "ST_Intersects(ST_SetSRID('BOX(#{bbox[0]} #{bbox[1]}, #{bbox[2]} #{bbox[3]})'::box2d, 4326), geom)",
      :joins => :user,
      :limit => 100,
      :order => 'created_at DESC')
  end
end
