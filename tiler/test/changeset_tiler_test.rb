$:.unshift File.absolute_path(File.dirname(__FILE__)) + '/../lib'

require 'pg'
require 'test/unit'
require 'yaml'
require 'changeset_tiler'

require './common'

class ChangesetTilerTest < Test::Unit::TestCase
  include TestCommon

  # Tag changes in Zagreb and Budapest place nodes.
  def test_12917265
    setup_changeset_test(12917265)
    assert_equal(6, find_changes('el_type' => 'N').size)
    #assert_equal(3, @tiles.size)
  end

  def test_13477045
    setup_changeset_test(13477045)
    assert_equal(0, find_changes('el_type' => 'N').size)
    assert_equal(26, find_changes('el_type' => 'W').size)
  end

  def test_14234906_multiple_way_versions
    setup_changeset_test(14234906)
  end

  def test_14459096_affected_way_with_version_1
    setup_changeset_test(14459096)
    assert_equal(0, find_changes('el_type' => 'N').size)
    assert_equal(1, find_changes('el_type' => 'W').size)
  end

  def test_14458340_affected_way
    setup_changeset_test(14458340)
    assert_equal(0, find_changes('el_type' => 'N').size)
    assert_equal(1, find_changes('el_type' => 'W').size)
  end

  def test_14698811
    setup_changeset_test(14698811)
    assert_equal(1, find_changes('el_type' => 'W', 'el_id' => '201787145', 'version' => '1').size)
  end

  def test_14698916
    setup_changeset_test(14698916)
    assert_equal(1, find_changes('el_type' => 'W', 'el_id' => '201787145', 'version' => '2').size)
  end

  def test_14820799_created_way
    setup_changeset_test(14820799)
    assert_equal(0, find_changes('el_type' => 'N').size)
    assert_equal(1, find_changes('el_type' => 'W', 'action' => 'CREATE', 'el_id' => '203232361').size)
  end

  def test_14797380_created_area
    setup_changeset_test(14797380)
    assert_equal(0, find_changes('el_type' => 'N').size)
    assert_equal(1, find_changes('el_type' => 'W', 'action' => 'CREATE', 'el_id' => '203011417').size)
  end

  def test_14796945
    setup_changeset_test(14796945)
    assert_equal(0, find_changes('el_type' => 'N').size)
    assert_equal(4, find_changes('el_type' => 'W').size)
    assert_equal(1, find_changes('el_type' => 'W', 'action' => 'CREATE', 'el_id' => '203008418').size)
  end

  def test_13387349
    setup_changeset_test(13387349)
  end

  def test_13394677
    setup_changeset_test(13394677)
  end

  def test_13477568
    setup_changeset_test(13477568)
    for tile in @tiles
      if (tile['x'].to_i == 36175) and (tile['y'].to_i == 22851)
        geom_arr = pg_parse_geom_array(tile['geom'])
        prev_geom_arr = pg_parse_geom_array(tile['prev_geom'])
        #p @changes_h[30]['tags'] != @changes_h[30]['prev_tags']
        #p @changes_h[30]
        #p geom_arr[0]
        #p prev_geom_arr[0]
      end
    end
  end

  def test_13473237
    setup_changeset_test(13473237)
  end

  def test_14699204
    setup_changeset_test(14699204)
  end

  def test_13426127
    setup_changeset_test(13426127)
  end

  def test_13258073
    setup_changeset_test(13258073)
    assert_equal(1, find_changes('el_type' => 'N', 'el_id' => '420302052', 'action' => 'DELETE').size)
  end

  def test_14429223_deleted_ways
    setup_changeset_test(14429223)
    assert_equal(1, find_changes('el_type' => 'W', 'el_id' => '198336783', 'version' => '2').size)
  end

  def test_11193918
    setup_changeset_test(11193918)
    assert_equal(2, find_changes('el_type' => 'N').size)
    assert_equal(1, find_changes('el_id' => '1703304298').size)
    assert_equal(10, find_changes('el_type' => 'W').size)
  end

  def test_13018562
    setup_changeset_test(13018562)
  end

  def test_13223248_misaligned_way
    setup_changeset_test(13223248)

    way = find_changes('el_type' => 'W', 'el_id' => '166444532', 'version' => '4')
    assert_equal(1, way.size)
    #assert_equal(11, way[0]['nodes_len'].to_i)
    #assert(way[0]['geom_astext'].include?('18.650061'))

    way = find_changes('el_type' => 'W', 'el_id' => '169856888', 'version' => '1')
    assert_equal(1, way.size)
    #assert_equal('4', way[0]['nodes_len'])
    #assert(way[0]['geom_astext'].include?('18.650061'))
  end

  def test_13294164
    setup_changeset_test(13294164)
    assert_equal(9, find_changes('el_type' => 'W').size)

    # traffic_signals changed position - should be a change for that.
    changes = find_changes('el_type' => 'N', 'el_id' => '244942711')
    assert_equal(1, changes.size)
  end

  def test_13294164
    setup_changeset_test(13294164)
    assert_equal(9, find_changes('el_type' => 'W').size)

    # traffic_signals changed position - should be a change for that.
    changes = find_changes('el_type' => 'N', 'el_id' => '244942711')
    assert_equal(1, changes.size)
  end

  def test_16951072
    setup_changeset_test(16951072)
    assert_equal(2, find_changes('el_type' => 'W').size)
  end

  def test_16863679
    setup_changeset_test(16863679)
    assert_equal(3, find_changes('el_type' => 'W').size)
  end

  def test_14530383_forest_with_small_change_and_multiple_changes_of_one_object
    setup_changeset_test(14530383)
    forest_change = find_changes('el_type' => 'W', 'el_id' => '161116311', 'version' => '3')
    p forest_change
    assert_equal(1, forest_change.size)
    forest_tile = @tiles.find {|tile| tile['changes'].include?(forest_change[0]['id'])}
    # Tile geom should not include the whole forest (it was a bug once).
    assert(!forest_tile['geom_astext'].include?('50.5478683'))

    # Now let's test way 174644591 which has 5 revisions in this changeset.
    assert_equal(4, find_changes('el_type' => 'W', 'action' => 'DELETE').size)
  end

  def test_18915_empty_geomcollection_error
    setup_changeset_test(18915)
  end

  def test_nan
    setup_changeset_test(14863424)
  end

  def test_collection
    setup_changeset_test(14836474)
  end

  # Way 16105282 has no-change versions.
  def test_7082
    setup_changeset_test(7082)
    p find_changes('el_type' => 'W', 'el_id' => '16105282')[0]
    p find_changes('el_type' => 'W', 'el_id' => '16105282')[1]
    assert_equal(1, find_changes('el_type' => 'W', 'el_id' => '16105282').size)
  end
end
