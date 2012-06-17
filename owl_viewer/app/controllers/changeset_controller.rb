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
    common_map(" AND (strftime('%s','now') - time) < 86400", 0.5)
  end

  def weeklymap
    @title = "Map of changes over the past week"
    common_map(" AND (strftime('%s','now') - time) < 806400", 0.15)
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
      where_sql = QuadTile.tiles_for_ranges(@ranges)
      @changesets = find_changesets_among_tiles(tiles, 0, 0)
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

    return filtered_tiles
  end

  def find_changesets_among_tiles(tiles, qtile_prefix, depth)
    changesets = Array.new

    # (These are hexadecitiles, not quadtiles)

    table_name = changes_table_name(qtile, depth)
    tile_sql = "(#{tiles.join(',')})"
    changesets.concat(ActiveRecord::Base.connection.select_rows("SELECT c.changeset, max(c.time) AS time, COUNT(distinct c.tile) AS num_tiles
                                                                 FROM #{table_name} c
                                                                 WHERE c.tile IN #{tile_sql}
                                                                 GROUP BY c.changeset
                                                                 ORDER BY time desc
                                                                 LIMIT 100").collect {|x,y,n,u| [x.to_i, Time.parse(y), n.to_i, u.to_i] })

    # Don't traverse children if we're already at the deep end or already have 100 changesets at this level
    if depth < MAX_DEPTH and changesets.length >= 100
      for i in 0..(1 << CHANGES_BITS)
        prefix = (qtile_prefix << CHANGES_BITS) | i
        tiles_for_child = filter_tiles_in_qtile(tiles, prefix, depth + 1)
        if tiles_for_child.size > 0
          changesets.concat(find_changesets_among_tiles(tiles_for_child, prefix, depth + 1))
        end
      end
    end

    return changesets
  end

  def find_changed_tiles_among_tiles(where_time, tiles, qtile_prefix, depth)
    changed_tiles = Array.new

    # (These are hexadecitiles, not quadtiles)

    table_name = changes_table_name(qtile_prefix, depth)
    tile_sql = "tile IN (#{tiles.join(',')})" if tiles.size > 0 else ""
    changed_tiles.concat(ActiveRecord::Base.connection.select_values("SELECT DISTINCT tile
                                                                      FROM #{table_name}
                                                                      WHERE #{tile_sql}#{where_time}").collect {|x| x.to_i})

    # Don't traverse children if we're already at the deep end
    if depth < MAX_DEPTH
      for i in 0..(1 << CHANGES_BITS)
        prefix = (qtile_prefix << CHANGES_BITS) | i
        tiles_for_child = filter_tiles_in_qtile(tiles, prefix, depth + 1)
        if tiles_for_child.size > 0
          changed_tiles.concat(find_changed_tiles_among_tiles(where_time, tiles_for_child, prefix, depth + 1))
        end
      end
    end

    return changed_tiles
  end

  def common_map(where_time, max_area)
    @tiles = []
    unless params['bbox'].nil?
      bbox = params['bbox'].split(/,/).map { |x| x.to_f }
      area = (bbox[2] - bbox[0]) * (bbox[3] - bbox[1])
      #RAILS_DEFAULT_LOGGER.debug("area: #{area}")
      if (area < max_area)
        tiles_in_area = QuadTile.tiles_for_area(*bbox)
        # Chase down all the child tables to look for tiles with changes inside the bbox
        @tiles = find_changed_tiles_among_tiles(where_time, tiles_in_area, 0, 0)
      end
    end
    @tiles = @tiles.sort.uniq
    render :layout => 'with_map'
  end
end
