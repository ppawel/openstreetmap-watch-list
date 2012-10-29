class ChangesetController < ApplicationController
  def changesets
    bbox = params[:bbox].split(/,/).map { |x| x.to_f }
    @changesets = find_changesets_by_bbox(bbox)
    render :template => "changeset/changesets.#{params[:format]}", :layout => false
  end

  def tile
    bbox = xyz_to_bbox(params[:x].to_i, params[:y].to_i, params[:zoom].to_i)
    @changesets = find_changesets_by_bbox(bbox)
    render :template => "changeset/changesets.#{params[:format]}", :layout => false
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
