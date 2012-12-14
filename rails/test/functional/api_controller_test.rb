require 'test_helper'

class ApiControllerTest < ActionController::TestCase
  # Replace this with your real tests.
  test "the truth" do
    load_changeset(12917265)
    get(:changesets_tile_json, {:x => 36234, :y => 22917, :zoom => 16})
    changesets = assigns['changesets']
    assert_equal(1, changesets.size)
  end

  def load_changeset(changeset_id)
    system('psql -a -d owl_test -c "\copy changesets from ' + Rails.root.to_s + '/test/data/' + changeset_id.to_s + '-changeset.csv"')
    system('psql -a -d owl_test -c "\copy changes from ' + Rails.root.to_s + '/test/data/' + changeset_id.to_s + '-changes.csv"')
    system('psql -a -d owl_test -c "\copy tiles from ' + Rails.root.to_s + '/test/data/' + changeset_id.to_s + '-tiles.csv"')
  end
end
