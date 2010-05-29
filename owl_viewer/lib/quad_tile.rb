module QuadTile
  def self.xy2tile(x, y)
    x = (x | (x << 8)) & 0x00ff00ff
    x = (x | (x << 4)) & 0x0f0f0f0f
    x = (x | (x << 2)) & 0x33333333
    x = (x | (x << 1)) & 0x55555555
    
    y = (y | (y << 8)) & 0x00ff00ff
    y = (y | (y << 4)) & 0x0f0f0f0f
    y = (y | (y << 2)) & 0x33333333
    y = (y | (y << 1)) & 0x55555555
    
    return (x << 1) | y
  end

  def self.tile2xy(t)
    x = (t >> 1)       & 0x55555555
    x = (x | (x >> 1)) & 0x33333333
    x = (x | (x >> 2)) & 0x0f0f0f0f
    x = (x | (x >> 4)) & 0x00ff00ff
    x = (x | (x >> 8)) & 0x0000ffff

    y = t              & 0x55555555
    y = (y | (y >> 1)) & 0x33333333
    y = (y | (y >> 2)) & 0x0f0f0f0f
    y = (y | (y >> 4)) & 0x00ff00ff
    y = (y | (y >> 8)) & 0x0000ffff

    return [x, y]
  end

  def self.x2lon(x)
    (x * 2**16 - 2**31) / 10000000.0
  end

  def self.y2lat(y)
    (y * 2**16 - 2**31) / 10000000.0
  end

  def self.lon2x(lon)
    (lon * 10000000.0 + 2**31) / 2**16
  end

  def self.lat2y(lat)
    (lat * 10000000.0 + 2**31) / 2**16
  end

  def self.tiles_for_area(minlon, minlat, maxlon, maxlat)
    minx = lon2x(minlon).floor
    maxx = lon2x(maxlon).ceil
    miny = lat2y(minlat).floor
    maxy = lat2y(maxlat).ceil
    tiles = []

    minx.upto(maxx) do |x|
      miny.upto(maxy) do |y|
        tiles << xy2tile(x, y)
      end
    end
    
    return tiles
  end

  def self.iterate_tile_ranges(ranges)
    tiles = []
    ranges.each do |r|
      if r.length == 2
        p1 = tile2xy(r[0])
        p2 = tile2xy(r[1])
        [p1[0],p2[0]].min.upto([p1[0],p2[0]].max) do |x|
          [p1[1],p2[1]].min.upto([p1[1],p2[1]].max) do |y|
            tiles << xy2tile(x, y)
          end
        end
      else
        tiles << r[0]
      end
    end

    first = last = nil

    tiles.sort.uniq.each do |tile|
      if last.nil?
        first = last = tile
      elsif tile == last + 1
        last = tile
      else
        yield first, last

        first = last = tile
      end
    end

    yield first, last unless last.nil?
  end

  def self.iterate_tiles_for_area(minlon, minlat, maxlon, maxlat)
    tiles = tiles_for_area(minlon, minlat, maxlon, maxlat)
    first = last = nil

    tiles.sort.each do |tile|
      if last.nil?
        first = last = tile
      elsif tile == last + 1
        last = tile
      else
        yield first, last

        first = last = tile
      end
    end

    yield first, last unless last.nil?
  end

  def self.sql_for_area(minlon, minlat, maxlon, maxlat, prefix = "")
    sql = Array.new
    single = Array.new

    iterate_tiles_for_area(minlon, minlat, maxlon, maxlat) do |first,last|
      if first == last
        single.push(first)
      else
        sql.push("#{prefix}tile BETWEEN #{first} AND #{last}")
      end
    end

    sql.push("#{prefix}tile IN (#{single.join(',')})") if single.size > 0

    return "( " + sql.join(" OR ") + " )"
  end

  def self.ranges_size(ranges)
    ranges.inject(0) do |s, r|
      x0,y0 = tile2xy(r[0])
      x1,y1 = tile2xy(r[1])
      s + (x0 - x1 + 1).abs * (y0 - y1 + 1).abs
    end
  end

  def self.sql_for_ranges(ranges, prefix = "")
    sql = Array.new
    single = Array.new

    iterate_tile_ranges(ranges) do |first, last|
      if first == last
        single << first
      else
        sql << "#{prefix}tile between #{first} and #{last}"
      end
    end

    sql << "#{prefix}tile in (" + single.join(",") + ")" if single.size > 0

    sql.join " or "
  end
end
