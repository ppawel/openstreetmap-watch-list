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

  def test_14429223_deleted_ways
    setup_way_tiler_test(14429223)
    #p @conn.exec("SELECT * FROM way_revisions where way_id = 198336783").to_a
    #p @conn.exec("SELECT distinct el_id, el_version, el_rev FROM way_tiles where el_id = 198336783").to_a
  end

  def test_empty_geom_collection
    setup_way_tiler_test(18915)
    @way_tiler.create_way_tiles(14797290)

    p @conn.exec(
      "SELECT *, ST_AsText(OWL_MakeLine(w.nodes, rev.tstamp)) FROM way_revisions rev
        INNER JOIN ways w ON (w.id = rev.way_id AND w.version = rev.version)
        WHERE ST_IsEmpty(OWL_MakeLine(w.nodes, rev.tstamp))").to_a

    #p @conn.exec("SELECT * FROM way_revisions where way_id = 198336783").to_a
    #p @conn.exec("SELECT distinct el_id, el_version, el_rev FROM way_tiles where el_id = 198336783").to_a
  end

  def setup_way_tiler_test(changeset_id)
    setup_db
    load_changeset(changeset_id)
    @way_tiler = Tiler::WayTiler.new(@conn)
    # Create tiles for all ways in the database.
    for way in @conn.exec("SELECT DISTINCT id FROM ways").to_a
      #@way_tiler.create_way_tiles(way['id'])
    end
  end
end
