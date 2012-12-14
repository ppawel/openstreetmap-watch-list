require 'test_helper'

class ApiControllerTest < ActionController::TestCase
  test "Retrieving a JSON tile" do
    load_changeset(12917265)
    get(:changesets_tile_json, {:x => 36234, :y => 22917, :zoom => 16})
    changesets = assigns['changesets']
    assert_equal(1, changesets.size)
    json = JSON[@response.body]
    assert_equal(1, json.size)
    assert(!json[0].include?('geojson'))
    assert(json[0].include?('changes'))
    assert_equal(1, json[0]['changes'].size)
    assert_equal('t', json[0]['changes'][0]['tags_changed'])
    assert_equal('yes', json[0]['changes'][0]['tags']['capital'])
    assert_equal('1702297', json[0]['changes'][0]['tags']['population'])
    assert_equal('1702297', json[0]['changes'][0]['prev_tags']['population'])
    assert_equal('2', json[0]['changes'][0]['tags']['admin_level'])
    assert_equal(nil, json[0]['changes'][0]['prev_tags']['admin_level'])
  end

  def load_changeset(changeset_id)
    system('psql -a -d owl_test -c "\copy changesets from ' + Rails.root.to_s + '/test/data/' + changeset_id.to_s + '-changeset.csv"')
    system('psql -a -d owl_test -c "\copy changes from ' + Rails.root.to_s + '/test/data/' + changeset_id.to_s + '-changes.csv"')
    system('psql -a -d owl_test -c "\copy tiles from ' + Rails.root.to_s + '/test/data/' + changeset_id.to_s + '-tiles.csv"')
  end
end
