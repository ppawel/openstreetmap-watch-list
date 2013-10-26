require 'test_helper'
require 'test/common'

class ChangesetApiControllerTest < ActionController::TestCase
  include TestCommon

  test "13473782" do
    setup_changeset_test(13473782)
    verify_api_response
  end

  def verify_api_response
    # For every tile we request it through the API and verify JSON from the response
    for tile in conn.query('SELECT * FROM changeset_tiles WHERE zoom = 18').to_a do
      get(:changesets_tile_json, {:x => tile['x'].to_i, :y => tile['y'].to_i, :zoom => 18})
      for changeset in JSON[@response.body] do
        change_ids = []
        for change in changeset['changes'] do
          change_ids << change['id']
        end
        assert_equal(change_ids.uniq, change_ids, 'Changeset has duplicate changes: ' + changeset.to_s)
      end
    end
  end
end
