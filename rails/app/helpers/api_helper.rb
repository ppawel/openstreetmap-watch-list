module ApiHelper
  def xy2tile(x, y)
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

  def tile2xy(t)
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

  def x2lon(x)
    (x * 2**16 - 2**31) / 10000000.0
  end

  def y2lat(y)
    (y * 2**16 - 2**31) / 10000000.0
  end

  def lon2x(lon)
    (lon * 10000000.0 + 2**31) / 2**16
  end

  def lat2y(lat)
    (lat * 10000000.0 + 2**31) / 2**16
  end
end
