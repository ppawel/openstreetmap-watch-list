$:.unshift File.absolute_path(File.dirname(__FILE__)) + '/../lib'

require 'pg'
require 'test/unit'
require 'yaml'
require 'tiler'

require './common'

class TilerTest < Test::Unit::TestCase
  include TestCommon

  # Tag changes in Zagreb and Budapest place nodes.
  def test_12917265
    setup_changeset_test(12917265)
    assert_equal(3, @tiles.size)
    assert_equal(3, find_changes('tags_changed' => 't').size)
  end

  def test_13294164
    setup_changeset_test(13294164)
    assert_equal(9, find_changes('el_type' => 'W').size)

    # traffic_signals changed position - should be a change for that.
    changes = find_changes('el_type' => 'N', 'el_id' => '244942711')
    assert_equal(1, changes.size)
    assert_equal('t', changes[0]['geom_changed'])
  end

  def test_9769694
    setup_changeset_test(9769694)
    assert_equal(1, find_changes('el_id' => '27833730', 'el_version' => '14').size)
  end

  def test_11193918
    setup_changeset_test(11193918)
    assert_equal(2, find_changes('el_type' => 'N').size)
    assert_equal(1, find_changes('el_id' => '1703304298').size)
    assert_equal(7, find_changes('el_type' => 'W').size)
  end

  def test_13477045
    setup_changeset_test(13477045)
    assert_equal(0, find_changes('el_type' => 'N').size)
    assert_equal(25, find_changes('el_type' => 'W').size)
  end

  def test_13018562
    setup_changeset_test(13018562)
  end

  def test_13258073
    setup_changeset_test(13258073)
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

  def test_14370470_validate_ways
    setup_changeset_test(14370470)
    assert_equal(1, find_changes('el_type' => 'W', 'el_id' => '26393755', 'el_version' => '7').size)
  end

  def test_13223248_misaligned_way
    setup_changeset_test(13223248)

    way = find_changes('el_type' => 'W', 'el_id' => '166444532', 'el_version' => '4')
    assert_equal(1, way.size)
    assert_equal('11', way[0]['nodes_len'])
    assert(way[0]['geom_astext'].include?('18.650061'))

    way = find_changes('el_type' => 'W', 'el_id' => '169856888', 'el_version' => '1')
    assert_equal(1, way.size)
    assert_equal('4', way[0]['nodes_len'])
    assert(way[0]['geom_astext'].include?('18.650061'))
  end

  def test_14429223_deleted_ways
    setup_changeset_test(14429223)
    assert_equal(1, find_changes('el_type' => 'W', 'el_id' => '198336783', 'el_version' => '2').size)
  end

  def test_14211906_only_nodes
    setup_changeset_test(14211906)
    assert_equal(0, find_changes('el_type' => 'W').size)
    assert_equal(5998, find_changes('el_type' => 'N').size)
  end

  def test_14530383_forest_with_small_change_and_multiple_changes_of_one_object
    setup_changeset_test(14530383)
    forest_change = find_changes('el_type' => 'W', 'el_id' => '161116311', 'el_version' => '3')
    assert_equal(1, forest_change.size)
    forest_tile = @tiles.find {|tile| tile['changes'].include?(forest_change[0]['id'])}
    # Tile geom should not include the whole forest (it was a bug once).
    assert(!forest_tile['geom_astext'].include?('50.5478683'))

    # Now let's test way 174644591 which has 5 revisions in this changeset.
    p find_changes('el_type' => 'W', 'el_action' => 'DELETE').collect{|change| change['el_id']}
    assert_equal(4, find_changes('el_type' => 'W', 'el_action' => 'DELETE').size)
  end
end
