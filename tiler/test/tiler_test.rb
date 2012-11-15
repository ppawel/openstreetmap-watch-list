$:.unshift File.absolute_path(File.dirname(__FILE__)) + '/../lib'

require 'pg'
require 'test/unit'
require 'yaml'
require 'tiler'

class TilerTest < Test::Unit::TestCase
  def test_13859877
    count = setup_changeset_test(13859877)
    assert_equal(37, count)
  end

  def test_13795865
    count = setup_changeset_test(13795865)
    assert_equal(235, count)
  end

  # Caused ERROR:  GEOSUnaryUnion: TopologyException: found non-noded intersection between LINESTRING (-35.2943
  # -5.91695, -35.2943 -5.91695) and LINESTRING (-35.2944 -5.91685, -35.2943 -5.91695) at -35.294336083167607
  # -5.9169522831676078 (PG::Error)
  def test_13729819
    count = setup_changeset_test(13729819)
    assert_equal(235, count)
  end

  # Caused segfault on zark with GEOS 3.3.5 and PostGIS 2.0.1.
  def test_13743410
    count = setup_changeset_test(13743410)
    assert_equal(235, count)
  end

  # ERROR:  GEOSUnaryUnion: TopologyException: found non-noded intersection between LINESTRING (7.85872 48.7632, 7.85864
  # 48.7631) and LINESTRING (7.85864 48.7631, 7.85864 48.7631) at 7.8586359309515483 48.763120943817903 (PG::Error)
  def test_13695113
    count = setup_changeset_test(13695113)
    assert_equal(235, count)
  end

  def setup_changeset_test(id)
    setup_db
    load_changeset(id)
    tiler = Tiler::Tiler.new(@conn)
    tiler.generate(16, id, prepare_options)
  end

=begin
  def test_basic_tiling
    setup_db
    exec_sql_file('test_data.sql')
    tiler = Tiler::Tiler.new(@conn)
    count = tiler.generate(16, 13517262, prepare_options)
    assert_equal(62, count)
  end

  def test_invalid_geometry
    setup_db
    exec_sql_file('test_changeset_13440045.sql')
    tiler = Tiler::Tiler.new(@conn)
    count = tiler.generate(16, 13440045, prepare_options)
    assert_equal(14, count)
  end

  # This checks for simple tiling stuff plus a rounding issue that occurred on zark with geography type.
  def test_simple_way
    setup_db
    exec_sql_file('test_simple_way.sql')
    tiler = Tiler::Tiler.new(@conn)
    count = tiler.generate(16, 13440045, prepare_options)
    assert_equal(5, count)

    # Gather points to check if they are represented in tiles after tiling.
    points = []
    for point in @conn.query('SELECT ST_AsText((g.dump).geom) FROM (SELECT ST_DumpPoints(current_geom) dump FROM
        changes) g').to_a
      points << point['st_astext'].gsub('POINT(', '').gsub(')', '')
    end

    # Now check that tile geometry contains sane data (without changed coordinates).
    geom_string = @conn.query('SELECT ST_AsText(geom) FROM changeset_tiles').to_a.reduce('') {|total, row| total + row['st_astext']}

    assert_equal(false, geom_string.include?('999999'))
    assert_equal(false, geom_string.include?('5180885999359'))

    for point in points
      assert_equal(true, geom_string.include?(point))
    end
  end
=end
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
  end

  def exec_sql_file(file)
    @conn.transaction do |c|
      @conn.exec(File.open(file).read)
    end
  end

  def load_changeset(id)
    @conn.transaction do |c|
      @conn.exec("COPY changesets FROM STDIN;")
      File.open('changeset_' + id.to_s + '.csv').read.each_line do |line|
        @conn.put_copy_data(line)
      end
      @conn.put_copy_end

      @conn.exec("COPY changes FROM STDIN;")
      File.open('changes_' + id.to_s + '.csv').read.each_line do |line|
        @conn.put_copy_data(line)
      end
      @conn.put_copy_end
    end
  end
end
