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
  def changes_table_name(prefix, depth)
    if depth == 0
      return "changes"
    else
      hex = prefix.to_s(16)
      return "changes_" << hex.rjust(depth - hex.len, "0")
    end
  end

  def find_tiles(where_time, where_tile, qtile, depth)
    tiles = Array.new

    table_name = changes_table_name(qtile, depth)

    this_level = (ActiveRecord::Base.connection.select_values("select distinct tile from #{table_name} where #{where_sql}#{where_time}").collect {|x| x.to_i})

    # FIXME this is probably not a good check to use
    if this_level.length > 0
      for (uint32_t i = 0; i < (1u << CHANGES_BITS); ++i) {
          uint32_t prefix = (qtile_prefix << CHANGES_BITS) | i;
          string table = changes_table_name(prefix, depth + 1);

    return tiles
  end

  def common_map(where_time, max_area)
    @tiles = []
    unless params['bbox'].nil?
      bbox = params['bbox'].split(/,/).map { |x| x.to_f }
      area = (bbox[2] - bbox[0]) * (bbox[3] - bbox[1])
      #RAILS_DEFAULT_LOGGER.debug("area: #{area}")
      if (area < max_area)
        where_sql = QuadTile.sql_for_area(*bbox)
        @tiles = Array.new
        # Chase down all the child tables to look for tiles with changes inside the bbox
        
        # Start with changes
        prefix = ""
        depth = 0
        qindex = 0
        @tiles.append(ActiveRecord::Base.connection.select_values("select distinct tile from changes#{prefix} where #{where_sql}#{where_time}").collect {|x| x.to_i})
        # TODO Check the oldest item in this table and stop if there are items older than we want. Child tables always have stuff older than this table.
        # Query the child tables
        [0, 1, 2, 3].each do |qtchild|

        end
      end
    end
    render :layout => 'with_map'
  end
end
