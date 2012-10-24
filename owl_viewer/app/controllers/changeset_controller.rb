class ChangesetController < ApplicationController
  def tiles
    @id = params['id'].to_i
    @title = "Map of changes in changeset #{@id}"
    @tiles = find_tiles_for_changeset(@id, 0, 0)
    #@tiles = ActiveRecord::Base.connection.select_values("select distinct tile from changes where changeset = #{@id}").collect {|x| x.to_i}
    render :layout => 'with_map'
  end

  def tile
    @id = params['id'].to_i
    @title = "List of changes in tile #{@id}"
    tiles = Array.new()
    tiles << @id
    @changes = find_changes_among_tiles(tiles, 0, 0)
    #@changes = Change.find(:all, :conditions => ["tile = ?", @id], :order => "time desc, changeset desc, id desc, version desc", :limit => 100)
    @changeset_ids = @changes.collect { |c| c.changeset }.uniq
    if @changeset_ids.size > 0
      @cs2details = ActiveRecord::Base.connection.select_rows("SELECT cs.id,u.name,cs.comment,cs.created_by,cs.bot_tag
                                                               FROM changeset_details cs
                                                               JOIN users u ON cs.uid=u.id
                                                               WHERE cs.id IN (#{@changeset_ids.join(',')})").inject(Hash.new) { |h,x| h[x[0].to_i] = x[1..-1]; h }
    else
      @cs2details = Hash.new
    end
  end

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

  def feed
    @ranges = params['range'].split(",").collect { |l| l.split("-").collect{|i| i.to_i} }
    size = QuadTile.ranges_size(@ranges)
    if (size > 100000)
      RAILS_DEFAULT_LOGGER.info("rejected feed size: #{size}")
      @changesets = []
    else
      tiles = QuadTile.tiles_for_ranges(@ranges)
      @changesets = find_changesets_among_tiles(tiles, 0, 0)
    end
    csids = @changesets.collect { |cs| cs[0].to_i }
    if csids.size > 0
      cs_query = "SELECT cs.id,u.name,cs.comment,cs.created_by,cs.bot_tag
                  FROM changeset_details cs
                  JOIN users u ON cs.uid=u.id
                  WHERE cs.id in (#{csids.join(',')})"
      @cs2details = ActiveRecord::Base.connection.select_rows(cs_query).inject(Hash.new) { |h,x| h[x[0].to_i] = x[1..-1]; h }
    else
      @cs2details = Hash.new
    end
    # @users = ActiveRecord::Base.connection.select_rows("select id,name from users where id in (#{uids.join(',')})").inject(Hash.new) { |h,x| h[x[0].to_i] = x[1]; h }
  end

private
  MAX_DEPTH=3
  CHANGES_BITS=4

  def changes_table_name(prefix, depth)
    if depth == 0
      return "changes"
    else
      hex = prefix.to_s(16)
      return "changes_" << hex.rjust(depth - hex.length, "0")
    end
  end

  def filter_tiles_in_qtile(tiles, qtile_prefix, depth)
    filtered_tiles = Array.new

    # Only include tiles whose first depth bytes match qtile_prefix
    qtile_hex = qtile_prefix.to_s(16)
    qtile_hex = qtile_hex.rjust(depth - qtile_hex.length, "0")
    tiles.each do |tile|
      tile_hex = tile.to_s(16)[0, depth]
      if tile_hex == qtile_hex
        filtered_tiles << tile
      end
    end

    return filtered_tiles.uniq.sort
  end

  def find_tiles_for_changeset(changeset, qtile_prefix, depth)
    tiles = []

    # (These are hexadecitiles, not quadtiles)

    # Don't traverse children if we're already at the deep end or already have 100 changesets at this level
    if depth < MAX_DEPTH
      for i in 0..((1 << CHANGES_BITS) - 1)
        prefix = (qtile_prefix << CHANGES_BITS) | i
        tiles.concat(find_tiles_for_changeset(changeset, prefix, depth + 1))
      end
    end


    table_name = changes_table_name(qtile_prefix, depth)
    begin
        tiles.concat(ActiveRecord::Base.connection.select_values("SELECT DISTINCT c.tile
                                                                  FROM #{table_name} c
                                                                  WHERE c.changeset = #{changeset}").collect {|x| x.to_i})
    rescue ActiveRecord::StatementInvalid => e
      # If this table doesn't exist, then there won't be any children
      return tiles
    end

    return tiles.uniq.sort
  end

    #@tiles = ActiveRecord::Base.connection.select_values("select distinct tile from changes where changeset = #{@id}").collect {|x| x.to_i}
  def find_changesets_among_tiles(tiles, qtile_prefix, depth)
    changesets = []

    # (These are hexadecitiles, not quadtiles)

    table_name = changes_table_name(qtile_prefix, depth)
    tile_sql = QuadTile.sql_for_tiles(tiles)
    changesets.concat(ActiveRecord::Base.connection.select_rows("SELECT c.changeset, max(c.time) AS time, COUNT(distinct c.tile) AS num_tiles
                                                                 FROM #{table_name} c
                                                                 WHERE #{tile_sql}
                                                                 GROUP BY c.changeset
                                                                 ORDER BY time desc
                                                                 LIMIT 100").collect {|x,y,n,u| [x.to_i, Time.parse(y), n.to_i, u.to_i] })

    # Don't traverse children if we're already at the deep end or already have 100 changesets at this level
    if depth < MAX_DEPTH and changesets.length < 100
      for i in 0..((1 << CHANGES_BITS) - 1)
        prefix = (qtile_prefix << CHANGES_BITS) | i
        tiles_for_child = filter_tiles_in_qtile(tiles, prefix, depth + 1)
        if tiles_for_child.size > 0
          changesets.concat(find_changesets_among_tiles(tiles_for_child, prefix, depth + 1))
        end
      end
    end

    return changesets
  end

  def find_changes_among_tiles(tiles, qtile_prefix, depth)
    changes = []

    table_name = changes_table_name(qtile_prefix, depth)
    tile_sql = QuadTile.sql_for_tiles(tiles)
    changes.concat(Change.find_by_sql("SELECT c.*
                                       FROM #{table_name} c
                                       WHERE #{tile_sql}
                                       LIMIT 100"))

    if depth < MAX_DEPTH and changes.length < 100
      for i in 0..((1 << CHANGES_BITS) - 1)
        prefix = (qtile_prefix << CHANGES_BITS) | i
        tiles_for_child = filter_tiles_in_qtile(tiles, prefix, depth + 1)
        if tiles_for_child.size > 0
          changes.concat(find_changes_among_tiles(tiles_for_child, prefix, depth + 1))
        end
      end
    end

    return changes
  end

  def find_changed_tiles_among_tiles(where_time, tiles, qtile_prefix, depth)
    changed_tiles = Array.new

    # (These are hexadecitiles, not quadtiles)

    table_name = changes_table_name(qtile_prefix, depth)
    if tiles.size > 0
      tile_sql = QuadTile.sql_for_tiles(tiles)
    else
      tiles_sql = ""
    end
    changed_tiles.concat(ActiveRecord::Base.connection.select_values("SELECT DISTINCT tile
                                                                      FROM #{table_name} c
                                                                      WHERE #{tile_sql}#{where_time}").collect {|x| x.to_i})

    # Don't traverse children if we're already at the deep end
    if depth < MAX_DEPTH
      for i in 0..((1 << CHANGES_BITS) - 1)
        prefix = (qtile_prefix << CHANGES_BITS) | i
        tiles_for_child = filter_tiles_in_qtile(tiles, prefix, depth + 1)
        if tiles_for_child.size > 0
          changed_tiles.concat(find_changed_tiles_among_tiles(where_time, tiles_for_child, prefix, depth + 1))
        end
      end
    end

    return changed_tiles.uniq.sort
  end

  def find_changesets_by_bbox(bbox)
    Changeset.find(:all,
      :select => "changesets.*, users.id AS user_id, users.name, ST_AsGeoJSON(ST_Intersection(ST_SetSRID(Box2D(ST_GeomFromText('LINESTRING(#{bbox[0]} #{bbox[1]}, #{bbox[2]} #{bbox[3]})')), 4326), geom), 5) AS geojson",
      :conditions => "ST_Intersects(ST_SetSRID(Box2D(ST_GeomFromText('LINESTRING(#{bbox[0]} #{bbox[1]}, #{bbox[2]} #{bbox[3]})')), 4326), geom)",
      :joins => :user,
      :limit => 100,
      :order => 'created_at DESC')
  end

  def common_map(where_time, max_area)
    @tiles = []
    unless params['bbox'].nil?
      bbox = params['bbox'].split(/,/).map { |x| x.to_f }
      area = (bbox[2] - bbox[0]) * (bbox[3] - bbox[1])
      @changesets = find_changesets_by_bbox(bbox)
      #RAILS_DEFAULT_LOGGER.debug("area: #{area}")
      if (area < max_area)
        tiles_in_area = QuadTile.tiles_for_area(*bbox)
        # Chase down all the child tables to look for tiles with changes inside the bbox
        #@tiles = find_changed_tiles_among_tiles(where_time, tiles_in_area, 0, 0)
      end
    end
    puts @tiles
    @tiles = @tiles.sort.uniq
    render :layout => 'with_map'
  end
end
