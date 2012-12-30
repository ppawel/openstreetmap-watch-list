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
    assert_equal(8, find_changes('el_type' => 'W').size)

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
    assert_equal(6, find_changes('el_type' => 'W').size)
  end

  def test_13477045
    setup_changeset_test(13477045)
    assert_equal(0, find_changes('el_type' => 'N').size)
    assert_equal(25, find_changes('el_type' => 'W').size)
  end

  def test_3155
    setup_changeset_test(3155)
    assert_equal(0, find_changes('el_type' => 'N').size)
    assert_equal(29, find_changes('el_type' => 'W').size)
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
  end
end
