require 'test_helper'

class ChangesetApiControllerTest < ActionController::TestCase
  test "13473782" do
    reset_db
    load_changeset(13473782)
  end

  def load_changeset(changeset_id)
    system('psql -a -d owl_test -c "\copy changesets from ' + Rails.root.to_s + '/testdata/' + changeset_id.to_s + '-changeset.csv"')
    system('psql -a -d owl_test -c "\copy nodes from ' + Rails.root.to_s + '/testdata/' + changeset_id.to_s + '-nodes.csv"')
    system('psql -a -d owl_test -c "\copy ways from ' + Rails.root.to_s + '/testdata/' + changeset_id.to_s + '-ways.csv"')

    conn = PGconn.open(:dbname => 'owl_test', :user => 'ppawel')
    tiler = Tiler::ChangesetTiler.new(conn)
    tiler.generate(18, changeset_id)

    for tile in conn.query('SELECT x, y FROM changeset_tiles WHERE zoom = 18').to_a do
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

  def reset_db
    system('psql -a -d owl_test -c "TRUNCATE changesets; TRUNCATE changeset_tiles; TRUNCATE nodes; TRUNCATE ways;"')
  end
end
