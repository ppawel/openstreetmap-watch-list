$:.unshift File.absolute_path(File.dirname(__FILE__)) + '/../lib'

require 'pg'
require 'test/unit'
require 'yaml'
require 'tiler'

class TilerTest < Test::Unit::TestCase
  # Tag changes in Zagreb and Budapest place nodes.
  def test_12917265
    count = setup_changeset_test(12917265)
    tiles = get_tiles
    assert_equal(2, tiles.size)
    changes = find_changes('origin' => 'NODE_TAGS_CHANGED')
    assert_equal(2, changes.size)
  end

  def test_13294164
    count = setup_changeset_test(13294164)
    tiles = get_tiles
    changes = find_changes('el_type' => 'W')
    assert_equal(10, changes.size)

    # traffic_signals changed position - should be a change for that.
    changes = find_changes('el_type' => 'N')
    assert_equal(1, changes.size)
  end

  def test_9769694
    count = setup_changeset_test(9769694)
    tiles = get_tiles
    changes = find_changes('el_id' => '27833730', 'el_version' => '14')
    assert_equal(1, changes.size)
  end

  def test_11193918
    count = setup_changeset_test(11193918)
    tiles = get_tiles
    changes = find_changes('el_type' => 'N')
    assert_equal(2, changes.size)
    changes = find_changes('el_id' => '1703304298')
    assert_equal(1, changes.size)
    changes = find_changes('el_type' => 'W')
    assert_equal(7, changes.size)
  end

  def test_13477045
    count = setup_changeset_test(13477045)
    tiles = get_tiles
    changes = find_changes('el_type' => 'N')
    assert_equal(0, changes.size)
    changes = find_changes('el_type' => 'W')
    assert_equal(25, changes.size)
  end

  ##
  # Utility methods
  #

  def setup_changeset_test(id)
    setup_db
    load_changeset(id)
    verify_changeset_data
    @tiler.generate(16, id, prepare_options)
  end

  def prepare_options
    options = {}
    options[:changesets] ||= ['all']
    options[:retile] = true
    options
  end

  def setup_db
    $config = YAML.load_file('../../rails/config/database.yml')['test']
    @conn = PGconn.open(:host => $config['host'], :port => $config['port'], :dbname => $config['database'],
      :user => $config['username'], :password => $config['password'])
    exec_sql_file('../../sql/owl_schema.sql')
    exec_sql_file('../../sql/owl_constraints.sql')
    #exec_sql_file('../../sql/owl_functions.sql')
    @tiler = Tiler::Tiler.new(@conn)
  end

  def exec_sql_file(file)
    @conn.exec(File.open(file).read)
  end

  def load_changeset(id)
    @conn.exec("COPY _changeset_data FROM STDIN;")
    File.open("data/#{id}.csv").read.each_line do |line|
      @conn.put_copy_data(line)
    end
    @conn.put_copy_end
  end

  def verify_changeset_data
    data = @conn.exec("SELECT id, version,
        ST_NumPoints(geom) AS num_points_geom, array_length(nodes, 1) AS num_points_arr,
        ST_NumPoints(prev_geom) AS prev_num_points_geom, array_length(prev_nodes, 1) AS prev_num_points_arr
      FROM _changeset_data WHERE type = 'W'").to_a
    for row in data
      assert_equal(row['num_points_arr'].to_i, row['num_points_geom'].to_i, "Wrong linestring for row: #{row.inspect}")
      #assert_equal(row['prev_num_points_arr'].to_i, row['prev_num_points_geom'].to_i, "Wrong prev linestring for row: #{row.inspect}")
    end
  end

  def get_changes
    @conn.exec("SELECT * FROM changes").to_a
  end

  def get_tiles
    @conn.exec("SELECT * FROM tiles").to_a
  end

  def find_changes(filters)
    a = []
    for change in get_changes
      match = true
      for k, v in filters
        match = (match and (change[k].to_s == v.to_s))
      end
      a << change if match
    end
    a
  end
end
