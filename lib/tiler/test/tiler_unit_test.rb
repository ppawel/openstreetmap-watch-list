$:.unshift File.absolute_path(File.dirname(__FILE__)) + '/../lib'

require 'pg'
require 'test/unit'
require 'yaml'
require 'changeset_tiler'

require 'test/common'

class TilerUnitTest < Test::Unit::TestCase
  include TestCommon

  def initialize(name = nil)
    @test_name = name
    super(name) unless name.nil?
  end

  def test_create_node
    setup_unit_test(@test_name)
    assert_equal(2, find_changes('el_type' => 'N').size)
  end

  def test_delete_node
    setup_unit_test(@test_name)
    assert_equal(2, find_changes('el_type' => 'N').size)
  end

  def test_move_node
    setup_unit_test(@test_name)
    assert_equal(2, find_changes('el_type' => 'N').size)
  end

  def test_move_node_same_changeset
    setup_unit_test(@test_name)
    assert_equal(2, find_changes('el_type' => 'N').size)
  end

  def test_tag_node
    setup_unit_test(@test_name)
    assert_equal(2, find_changes('el_type' => 'N').size)
  end

  def test_create_way
    setup_unit_test(@test_name)
    assert_equal(0, find_changes('el_type' => 'N').size)
    assert_equal(1, find_changes('el_type' => 'W').size)
  end

  def test_move_way
    setup_unit_test(@test_name)
    assert_equal(0, find_changes('el_type' => 'N', 'changeset_id' => 1).size)
    assert_equal(0, find_changes('el_type' => 'N', 'changeset_id' => 2).size)
    assert_equal(1, find_changes('el_type' => 'W', 'changeset_id' => 2).size)
    assert_equal(0, find_changes('el_type' => 'N', 'changeset_id' => 3).size)
    assert_equal(2, find_changes('el_type' => 'W', 'changeset_id' => 3).size)
  end
end
