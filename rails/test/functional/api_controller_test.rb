require 'test_helper'

class ApiControllerTest < ActionController::TestCase
  # Replace this with your real tests.
  test "the truth" do
    get(:changesets_tile_json, {:x => 12, :y => 12, :zoom => 16})
    changesets = assigns['changesets']
    assert_equal(1, changesets.size)
  end
end
