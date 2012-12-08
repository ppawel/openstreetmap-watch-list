$:.unshift File.absolute_path(File.dirname(__FILE__)) + '/../lib'

require 'pg'
require 'test/unit'
require 'yaml'
require 'tiler'

class TilerTest < Test::Unit::TestCase
  # Changes in Zagreb and Budapest place nodes.
  def test_12917265
    count = setup_changeset_test(12917265)
    changes = get_changes
    tiles = get_tiles
    puts tiles.inspect
    assert_equal(2, tiles.size)
    assert_equal(2, changes.size)
  end

  def setup_changeset_test(id)
    setup_db
    load_changeset(id)
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

  def get_changes
    @conn.exec("SELECT * FROM changes").to_a
  end

  def get_tiles
    @conn.exec("SELECT * FROM tiles").to_a
  end
end
