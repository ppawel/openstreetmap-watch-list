$:.unshift File.absolute_path(File.dirname(__FILE__))

require 'pg'
require 'test/unit'
require 'yaml'
require 'tiler'

class TilerTest < Test::Unit::TestCase
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
end
