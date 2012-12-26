$:.unshift File.absolute_path(File.dirname(__FILE__) + '/../lib/')

require 'test/unit'
require 'utils'

class UtilsTest < Test::Unit::TestCase
  def test_bbox_to_tiles
    tiles = bbox_to_tiles(18, [-95.2174366, 18.4330814, -95.2174366, 18.4330814])
    assert_equal(61736, tiles.to_a[0][0])
    assert_equal(117411, tiles.to_a[0][1])

    tiles = bbox_to_tiles(12, [-95.2143046, 18.450548, -95.2143046, 18.450548])
    assert_equal(964, tiles.to_a[0][0])
    assert_equal(1834, tiles.to_a[0][1])
  end

  def test_box2d_to_bbox
    bbox = box2d_to_bbox('BOX(5.8243191 45.1378079,5.8243191 45.1378079)')
    assert_equal(5.8243191, bbox[0])
    assert_equal(45.1378079, bbox[1])
    assert_equal(5.8243191, bbox[2])
    assert_equal(45.1378079, bbox[3])
  end

  def test_south_pole_tile
    puts latlon2tile(-90.0, 0.0, 18)
  end
end
