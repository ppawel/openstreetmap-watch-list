class ChangesetController < ApplicationController
  def tiles
    @id = params['id']
    @title = "Map of changes in changeset #{@id}"
    @tiles = ActiveRecord::Base.connection.select_values("select distinct tile from changes where changeset = #{@id}").collect {|x| x.to_i}
    render :layout => 'with_map'
  end

  def tile
    @id = params['id']
    @title = "List of changes in tile #{@id}"
    @changes = Change.find(:all, :conditions => ["tile = ?", @id], :order => "time desc, changeset desc, id desc, version desc", :limit => 100)
    @changeset_ids = @changes.collect { |c| c.changeset }.uniq
    if @changeset_ids.size > 0
      @cs2details = ActiveRecord::Base.connection.select_rows("select cs.id,u.name,cs.comment,cs.created_by,cs.bot_tag from changeset_details cs join users u on cs.uid=u.id where cs.id in (#{@changeset_ids.join(',')})").inject(Hash.new) { |h,x| h[x[0].to_i] = x[1..-1]; h }
    else
      @cs2details = Hash.new
    end
  end

  def dailymap
    @title = "Map of changes over the past day"
    common_map(" and age(time) < '1 day'", 0.5)
  end

  def weeklymap
    @title = "Map of changes over the past week"
    common_map(" and age(time) < '1 week'", 0.15)
  end

  def map
    @title = "Map of all changes"
    common_map("", 0.1)
  end

  def feed
    @ranges = params['range'].split(",").collect { |l| l.split("-").collect{|i| i.to_i} }
    size = QuadTile.ranges_size(@ranges)
    if (size > 100000) 
      RAILS_DEFAULT_LOGGER.info("rejected feed size: #{size}")
      @changesets = []
    else
      where_sql = QuadTile.sql_for_ranges(@ranges, "c.")
      @changesets = ActiveRecord::Base.connection.select_rows("select c.changeset, max(c.time) as time, count(distinct c.tile) as num_tiles from changes c where #{where_sql} group by c.changeset order by time desc limit 100").collect {|x,y,n,u| [x.to_i, Time.parse(y), n.to_i, u.to_i] }
    end
    csids = @changesets.collect { |cs| cs[0].to_i }
    if csids.size > 0
      cs_query = "select cs.id,u.name,cs.comment,cs.created_by,cs.bot_tag from changeset_details cs join users u on cs.uid=u.id where cs.id in (#{csids.join(',')})"
      @cs2details = ActiveRecord::Base.connection.select_rows(cs_query).inject(Hash.new) { |h,x| h[x[0].to_i] = x[1..-1]; h }
    else
      @cs2details = Hash.new
    end
    # @users = ActiveRecord::Base.connection.select_rows("select id,name from users where id in (#{uids.join(',')})").inject(Hash.new) { |h,x| h[x[0].to_i] = x[1]; h }
  end

private

  def common_map(where_time, max_area)
    @tiles = []
    unless params['bbox'].nil?
      bbox = params['bbox'].split(/,/).map { |x| x.to_f }
      area = (bbox[2] - bbox[0]) * (bbox[3] - bbox[1])
      #RAILS_DEFAULT_LOGGER.debug("area: #{area}")
      if (area < max_area) 
        where_sql = QuadTile.sql_for_area(*bbox)
        @tiles = ActiveRecord::Base.connection.select_values("select distinct tile from changes where #{where_sql}#{where_time}").collect {|x| x.to_i}
      end
    end
    render :layout => 'with_map'
  end
end
