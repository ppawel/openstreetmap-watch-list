$:.unshift File.absolute_path(File.dirname(__FILE__))

require 'pg'
require 'test/unit'
require 'yaml'
require 'tiler'

class TilerTest < Test::Unit::TestCase
  def test_basic_tiling
    setup_db
    tiler = Tiler::Tiler.new(@conn)
    #changeset_ids = tiler.get_changeset_ids(prepare_options)
    count = tiler.generate(16, 13517262, prepare_options)
    assert_equal(62, count)
    #puts changeset_ids.inspect
  end

  def prepare_options
    options = {}
    options[:changesets] ||= ['all']
    options[:geometry_tiles] ||= []
    options[:processing_change_limit] ||= 500000
    options[:summary_tiles] ||= []
    options[:retile] = true
    options
  end

  def setup_db
    $config = YAML.load_file('../../rails/config/database.yml')['test']
    @conn = PGconn.open(:host => $config['host'], :port => $config['port'], :dbname => $config['database'],
      :user => $config['username'], :password => $config['password'])
    exec_sql_file('../../sql/owl_schema.sql')
    exec_sql_file('test_data.sql')
  end

  def exec_sql_file(file)
    @conn.transaction do |c|
      @conn.exec(File.open(file).read)
    end
  end
end
