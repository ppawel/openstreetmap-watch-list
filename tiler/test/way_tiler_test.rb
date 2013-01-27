$:.unshift File.absolute_path(File.dirname(__FILE__)) + '/../lib'

require 'pg'
require 'test/unit'
require 'yaml'
require 'way_tiler'

require './common'

class WayTilerTest < Test::Unit::TestCase
  include TestCommon

  def test_11193918
    setup_way_tiler_test(11193918)
  end

  def setup_way_tiler_test(changeset_id)
    setup_db
    load_changeset(changeset_id)
    @way_tiler = Tiler::WayTiler.new(@conn)
    # Create tiles for all ways in the database.
    for way in @conn.exec("SELECT DISTINCT id FROM ways").to_a
      @way_tiler.create_way_tiles(way['id'])
    end
  end
end
