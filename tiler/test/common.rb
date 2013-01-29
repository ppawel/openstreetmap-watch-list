##
# Utility methods for tiler tests.
#
module TestCommon
  def setup_changeset_test(id)
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
    $config = YAML.load_file('../../rails/config/database.yml')['test']
    @conn = PGconn.open(:host => $config['host'], :port => $config['port'], :dbname => $config['database'],
      :user => $config['username'], :password => $config['password'])
    exec_sql_file('../../sql/owl_schema.sql')
    exec_sql_file('../../sql/owl_constraints.sql')
    exec_sql_file('../../sql/owl_functions.sql')
  end

  def exec_sql_file(file)
    @conn.exec(File.open(file).read)
  end

  def load_changeset(id)
    @conn.exec("COPY nodes FROM STDIN;")
    File.open("../../testdata/#{id}-nodes.csv").read.each_line do |line|
      @conn.put_copy_data(line)
    end
    @conn.put_copy_end
    @conn.exec("COPY ways FROM STDIN;")
    File.open("../../testdata/#{id}-ways.csv").read.each_line do |line|
      @conn.put_copy_data(line)
    end
    @conn.put_copy_end
    @conn.exec("SELECT OWL_CreateWayRevisions(w.id) FROM (SELECT DISTINCT id FROM ways) w")
  end

  def verify_changes(changeset_id)
    for way in find_changes('el_type' => 'W')
      # There should be at most 2 versions of a way (unless there are more of them in the changeset).
      if way['el_changeset_id'].to_i != changeset_id and way['version'].to_i > 1
        assert_equal(2, find_changes('el_type' => 'W', 'el_id' => way['el_id']).size,
          "Too many versions for way: #{way}")
      end
    end
  end

  def get_changes
    @conn.exec("SELECT * FROM changes").to_a
  end

  def get_tiles
    @conn.exec("SELECT *,
        array_length(geom, 1) AS geom_arr_len,
        array_length(prev_geom, 1) AS prev_geom_arr_len,
        array_length(changes, 1) AS change_arr_len,
        (select array_agg(st_astext(unnest)) from unnest(geom)) AS geom_astext
      FROM changeset_tiles WHERE zoom = 16").to_a
  end

  # Performs sanity checks on given tiles.
  def verify_tiles
    # Check if each change has a tile.
    change_ids = @changes_h.keys.sort.uniq
    change_ids_from_tiles = @tiles.collect {|tile| pg_parse_array(tile['changes'])}.flatten.sort.uniq
    assert_equal(change_ids, change_ids_from_tiles, change_ids - change_ids_from_tiles)

    for tile in @tiles
      # Every change should have an associated geom and prev_geom entry.
      assert_equal(tile['change_arr_len'].to_i, tile['geom_arr_len'].to_i)
      assert_equal(tile['change_arr_len'].to_i, tile['prev_geom_arr_len'].to_i)
      changes_arr = pg_parse_array(tile['changes'])

      geom_arr = pg_parse_geom_array(tile['geom'])
      prev_geom_arr = pg_parse_geom_array(tile['prev_geom'])

      for geom in geom_arr
        assert !geom.nil?
      end

      prev_geom_arr.each_with_index do |geom, index|
        change = @changes_h[changes_arr[index]]
        if change['el_version'].to_i != 1 and change['geom_changed'] == 't'
          #assert(geom != 'NULL', "prev_geom should not be null for change: #{change} and tile: #{tile}")
        end

        assert(geom != geom_arr[index], "geom and prev_geom are the same for tile: #{tile}")
      end
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
