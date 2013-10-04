require 'test_helper'

class ChangesetApiControllerTest < ActionController::TestCase
  def initialize(name = nil)
    @test_name = name
    super(name) unless name.nil?
  end

  test "create_node" do
    setup_test
    get(:changesets_tile_json, {:x => 36154, :y => 22260, :zoom => 16})
    changesets = assigns['changesets']
    json = JSON[@response.body]
    verify_response(json)
    assert_equal(1, changesets.size)
    assert_equal(1, json.size)
  end

  test "delete_node" do
    setup_test
    get(:changesets_tile_json, {:x => 36154, :y => 22260, :zoom => 16})
    changesets = assigns['changesets']
    json = JSON[@response.body]
    verify_response(json)
    assert_equal(1, changesets.size)
    assert_equal(1, json.size)
  end

  # Does some generic checks.
  def verify_response(changesets)
    for changeset in changesets
      for change in changeset['changes']
        if change['el_action'] == 'CREATE'
          assert(change['prev_tags'].nil?)
          assert(!change['tags'].nil?)
          assert(change['prev_geom'].nil?)
          assert(!change['geom'].nil?)
        elsif change['el_action'] == 'DELETE'
          #assert(change['tags'].nil?)
          assert(!change['prev_tags'].nil?)
          assert(change['geom'].nil?)
          assert(!change['prev_geom'].nil?)
        end
      end
    end
  end

  def setup_test
    reset_db
    load_data
  end

  def load_data
    system("psql -a -d owl_test -f test/fixtures/tiler_unit_#{@test_name.gsub('test_', '')}.sql")
    #system('psql -a -d owl_test -c "\copy nodes from ' + Rails.root.to_s + '/testdata/' + changeset_id.to_s + '-nodes.csv"')
    #system('psql -a -d owl_test -c "\copy ways from ' + Rails.root.to_s + '/testdata/' + changeset_id.to_s + '-ways.csv"')

    conn = PGconn.open(:dbname => 'owl_test', :user => 'ppawel')
    for i in 1..10 do
      conn.exec("INSERT INTO changesets VALUES (#{i}, 1, 'testuser', NOW(), NOW(), 'f', '', NULL, 0, NULL);")
    end
    tiler = Tiler::ChangesetTiler.new(conn)
    for id in conn.exec("SELECT changeset_id FROM nodes UNION SELECT changeset_id FROM ways").to_a.uniq do
      tiler.generate(16, id['changeset_id'].to_i, {:retile => true, :changes => true})
    end
  end

  def reset_db
    system('psql -a -d owl_test -c "TRUNCATE changesets; TRUNCATE changeset_tiles; TRUNCATE nodes; TRUNCATE ways;"')
  end
end
