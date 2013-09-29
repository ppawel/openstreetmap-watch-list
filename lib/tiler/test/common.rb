##
# Utility methods for tiler tests.
#
module TestCommon
  def setup_unit_test(test_name)
    setup_db
    exec_sql_file("test/fixtures/tiler_unit_#{test_name.gsub('test_', '')}.sql")
    @tiler = Tiler::ChangesetTiler.new(@conn)
    for id in @conn.exec("SELECT changeset_id FROM nodes UNION SELECT changeset_id FROM ways").to_a.uniq do
      @tiler.generate(16, id['changeset_id'].to_i, {:retile => true, :changes => true})
    end
    @changes = get_changes
    @changes_h = Hash[@changes.collect {|row| [row['id'].to_i, row]}]
    verify_changes(1)
    @tiles = get_tiles
    verify_tiles
  end

  def setup_changeset_test(id)
    puts "setup_changeset_test(#{id})"
    setup_db
    load_changeset(id)
    @tiler = Tiler::ChangesetTiler.new(@conn)
    @tiler.generate(16, id, {:retile => true, :changes => true})
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
    @conn.set_error_verbosity(0)
    exec_sql_file('db/sql/owl_schema.sql')
    exec_sql_file('db/sql/owl_constraints.sql')
    exec_sql_file('db/sql/owl_indexes.sql')
    exec_sql_file('db/sql/owl_functions.sql')
  end

  def exec_sql_file(file)
    @conn.exec(File.open(file).read)
  end

  def load_changeset(id, update_revs = true)
    if not File.exists?("testdata/#{id}-nodes.csv")
      raise "No test data for changeset #{id}"
    end

    puts 'Loading data...'

    @conn.exec("COPY nodes FROM STDIN;")

    File.open("testdata/#{id}-nodes.csv").read.each_line do |line|
      @conn.put_copy_data(line)
    end

    @conn.put_copy_end
    @conn.exec("COPY ways FROM STDIN;")

    File.open("testdata/#{id}-ways.csv").read.each_line do |line|
      @conn.put_copy_data(line)
    end

    @conn.put_copy_end
    @conn.exec("VACUUM ANALYZE")
  end

  def verify_changes(changeset_id)
    assert(@changes.size > 0, 'NO CHANGES?!')

    for change in @changes
      geom_changed = geom_changed(change)
      tags_changed = change['tags'] != change['prev_tags']
      #puts "changed #{change['el_id']} -- #{geom_changed} #{tags_changed}"
      assert((geom_changed or tags_changed or change['action'] == 'MODIFY' or change['action'] == 'DELETE'), "Change doesn't change anything: #{change}")
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
    @conn.exec("SELECT DISTINCT
        (c.unnest).id,
        (c.unnest).tstamp,
        (c.unnest).tags,
        (c.unnest).prev_tags,
        (c.unnest).el_type,
        (c.unnest).action,
        (c.unnest).el_id,
        (c.unnest).version
      FROM (SELECT unnest(changes) FROM changeset_tiles) c").to_a
  end

  def get_tiles
    @conn.exec("SELECT * FROM changeset_tiles WHERE zoom = 16").to_a
  end

  # Performs sanity checks on given tiles.
  def verify_tiles
    # Check if each change has a tile.
    change_ids = @changes_h.keys.sort.uniq
    change_ids_from_tiles = @tiles.collect {|tile| pg_parse_array(tile['changes'])}.flatten.sort.uniq
    #assert_equal(change_ids, change_ids_from_tiles,
    #  (change_ids - change_ids_from_tiles).collect {|id| @changes_h[id]})
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
