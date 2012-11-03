require 'test/unit'
require './tilerlib'

class TilerTest < Test::Unit::TestCase
  def test_bbox_to_tiles
    tiles = OWL::bbox_to_tiles(18, {'ymin' => -95.2174366, 'ymax' => -95.2174366, 'xmin' => 18.4330814, 'xmax' => 18.4330814})
    assert_equal(61736, tiles[0][0])
    assert_equal(117411, tiles[0][1])

    tiles = OWL::bbox_to_tiles(12, {'ymin' => -95.2143046, 'ymax' => -95.2143046, 'xmin' => 18.450548, 'xmax' => 18.450548})
    assert_equal(964, tiles[0][0])
    assert_equal(1834, tiles[0][1])
  end
end
