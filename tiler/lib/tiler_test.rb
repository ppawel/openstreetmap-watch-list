$:.unshift File.absolute_path(File.dirname(__FILE__))

require 'pg'
require 'test/unit'
require 'yaml'
require 'tiler'

class TilerTest < Test::Unit::TestCase
  def test_basic_tiling
    setup_db
    tiler = Tiler::Tiler.new(@conn)
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
