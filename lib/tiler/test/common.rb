require 'change'

##
# Utility methods for tiler tests.
#
module TestCommon
  TEST_ZOOM = 16

  def setup_unit_test(test_name)
    setup_db
    exec_sql_file("test/fixtures/tiler_unit_#{test_name.gsub('test_', '')}.sql")
    @tiler = Tiler::ChangesetTiler.new(@conn)
    for id in @conn.exec("SELECT changeset_id FROM nodes UNION SELECT changeset_id FROM ways").to_a.uniq do
      @tiler.generate(TEST_ZOOM, id['changeset_id'].to_i, {:retile => true, :changes => true})
    end
    @changes = get_changes
    verify_changes(1)
    @tiles = get_tiles
    verify_tiles
  end

  def setup_changeset_test(id)
    puts "setup_changeset_test(#{id})"
    setup_db
    load_changeset(id)
    @tiler = Tiler::ChangesetTiler.new(@conn)
    @tiler.generate(TEST_ZOOM, id, {:retile => true, :changes => true})
    @changes = get_changes
    @changes_h = Hash[@changes.collect {|row| [row['id'].to_i, row]}]
    verify_changes(id)
    @tiles = get_tiles
    verify_tiles
  end

  def setup_db
    $config = YAML.load_file('config/database.yml')['test']
    @conn = PGconn.open(:host => $config['host'], :port => $config['port'], :dbname => $config['database'],
      :user => $config['username'], :password => $config['password'])
    @conn.set_error_verbosity(1)
    exec_sql_file('db/sql/owl_schema.sql')
    exec_sql_file('db/sql/owl_constraints.sql')
    exec_sql_file('db/sql/owl_indexes.sql')
    exec_sql_file('db/sql/owl_functions.sql')
  end

  def exec_sql_file(file)
    @conn.exec(File.open(file).read)
  end

  def load_changeset(id)
    if not File.exists?("testdata/#{id}-nodes.csv")
      raise "No test data for changeset #{id}"
    end

    puts 'Loading data...'

    @conn.exec("COPY changesets FROM STDIN;")
    File.open("testdata/#{id}-changeset.csv").read.each_line do |line| @conn.put_copy_data(line) end
    @conn.put_copy_end

    @conn.exec("COPY nodes FROM STDIN;")
    File.open("testdata/#{id}-nodes.csv").read.each_line do |line| @conn.put_copy_data(line) end
    @conn.put_copy_end

    @conn.exec("COPY ways FROM STDIN;")
    File.open("testdata/#{id}-ways.csv").read.each_line do |line| @conn.put_copy_data(line) end
    @conn.put_copy_end

    @conn.exec("VACUUM ANALYZE")
  end

  def verify_changes(changeset_id)
    assert(@changes.size > 0, 'NO CHANGES?!')

    for change in @changes
      geom_changed = geom_changed(change)
      tags_changed = change['tags'] != change['prev_tags']
      nodes_changed = change['nodes'] != change['prev_nodes']
      #puts "changed #{change['el_id']} -- #{geom_changed} #{tags_changed}"
      #assert((nodes_changed or geom_changed or tags_changed or change['action'] == 'CREATE' or change['action'] == 'DELETE'),
      #  "Change doesn't change anything: #{change}")

      if change['action'] == 'CREATE'
        assert(!change['geom'].nil?, 'geom should not be null for change: ' + change.to_s)
        assert(change['prev_geom'].nil?, 'prev_geom should be null for change: ' + change.to_s)
        #assert(!change['tags'].empty?, 'tags should not be null for change: ' + change.to_s)
        #assert(change['prev_tags'].empty?, 'prev_tags should be null for change: ' + change.to_s)
      end

      if change['action'] == 'DELETE'
        assert(change['geom'].nil?, 'geom should be null for change: ' + change.to_s)
        assert(!change['prev_geom'].empty?, 'prev_geom should not be null for change: ' + change.to_s)
        #assert(change['tags'].empty?, 'tags should be null for change: ' + change.to_s)
        #assert(!change['prev_tags'].empty?, 'prev_tags should not be null for change: ' + change.to_s)
      end

      if change['action'] == 'MODIFY'
        assert(!change['geom'].nil?)
        #assert(!change['prev_geom'].nil?, 'prev_geom should not be null for change: ' + change.to_s)
      end
    end

    for way in find_changes('el_type' => 'W')
      # There should be at most 2 versions of a way (unless there are more of them in the changeset).
      if way['el_changeset_id'].to_i != changeset_id and way['version'].to_i > 1
      #  assert_equal(2, find_changes('el_type' => 'W', 'el_id' => way['el_id']).size,
       #   "Too many versions for way: #{way}")
      end
    end
  end

  def geom_changed(change)
    if change['el_type'] == 'N'
      return (@conn.exec("SELECT NOT n.geom = n2.geom
        FROM nodes n
        LEFT JOIN nodes n2 ON (n2.id = n.id AND n2.version = n.version - 1)
        WHERE n.id = #{change['el_id']} AND n.version = #{change['version']}").getvalue(0, 0) == 't')
    end
    if change['el_type'] == 'W'
      return (@conn.exec("SELECT NOT ST_Equals(OWL_MakeLine(w.nodes, '#{change['tstamp']}'),
          OWL_MakeLine(w.nodes, TIMESTAMP '#{change['tstamp']}' - INTERVAL '5 seconds'))
          OR OWL_MakeLine(w.nodes, '#{change['tstamp']}') IS NULL
        FROM ways w
        WHERE w.id = #{change['el_id']} AND w.version = #{change['version']}").getvalue(0, 0) == 't')
    end
  end

  def get_changes
    for change in @conn.exec("SELECT
        changeset_id,
        (c.unnest).id,
        (c.unnest).tstamp,
        (c.unnest).tags,
        (c.unnest).prev_tags,
        (c.unnest).el_type,
        (c.unnest).action,
        (c.unnest).el_id,
        (c.unnest).version,
        (c.unnest).nodes,
        (c.unnest).prev_nodes,
        (c.unnest).geom,
        (c.unnest).prev_geom
      FROM
      (
        SELECT changeset_id, unnest(OWL_MergeChanges(all_changes))
        FROM
        (
          SELECT changeset_id, array_accum(changes) AS all_changes
          FROM changeset_tiles WHERE zoom = #{TEST_ZOOM}
          GROUP BY changeset_id
        ) q
      ) c").to_a
    end
  end

  def get_tiles
    @conn.exec("SELECT * FROM changeset_tiles WHERE zoom = #{TEST_ZOOM}").to_a
  end

  # Performs sanity checks on tiles.
  def verify_tiles
    for tile in @tiles
      changes = Change.from_pg_array(tile['changes'])
      change_ids = []
      for change in changes do
          change_ids << change.id
      end
      assert_equal(change_ids.uniq, change_ids, 'Tile has duplicate changes: ' + tile.to_s)
    end
  end

  def find_changes(filters)
    a = []
    for change in @changes
      match = true
      for k, v in filters
        match = (match and (change[k].to_s == v.to_s))
      end
      a << change if match
    end
    a
  end
end
