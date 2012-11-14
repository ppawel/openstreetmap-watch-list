require 'test/unit'
require './tilerlib'

class UtilsTest < Test::Unit::TestCase
  def test_bbox_to_tiles
    tiles = OWL::bbox_to_tiles(18, {'ymin' => -95.2174366, 'ymax' => -95.2174366, 'xmin' => 18.4330814, 'xmax' => 18.4330814})
    assert_equal(61736, tiles[0][0])
    assert_equal(117411, tiles[0][1])

    tiles = OWL::bbox_to_tiles(12, {'ymin' => -95.2143046, 'ymax' => -95.2143046, 'xmin' => 18.450548, 'xmax' => 18.450548})
    assert_equal(964, tiles[0][0])
    assert_equal(1834, tiles[0][1])
  end

  def test_box2d_to_bbox
    bbox = box2d_to_bbox('BOX(5.8243191 45.1378079,5.8243191 45.1378079)')
    assert_equal(5.8243191, bbox[0])
    assert_equal(45.1378079, bbox[1])
    assert_equal(5.8243191, bbox[2])
    assert_equal(45.1378079, bbox[3])
  end
end
