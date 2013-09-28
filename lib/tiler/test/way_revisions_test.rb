$:.unshift File.absolute_path(File.dirname(__FILE__)) + '/../lib'

require 'pg'
require 'test/unit'
require 'yaml'
require 'way_tiler'

require './common'

class WayRevisionsTest < Test::Unit::TestCase
  include TestCommon

  def test_14459096
    setup_way_revisions_test(14459096)
    assert_equal(8, @revisions[35345926].size)

    @conn.exec("INSERT INTO nodes VALUES (414458276, 5, 5, true, true, 1679, '2012-12-31 03:22:11', 15469098,
      'a=>b'::hstore, '0101000020E610000082F80A1C1AC753C043BF5BC587E74540'::geometry(POINT, 4326))")
    @conn.exec("TRUNCATE way_revisions")
    @conn.exec("SELECT OWL_CreateWayRevisions(w.id, true) FROM (SELECT DISTINCT id FROM ways) w")
    verify_way_revisions
    assert_equal(9, @revisions[35345926].size)

    @conn.exec("INSERT INTO nodes VALUES (414458276, 6, 6, true, true, 1679, '2012-12-31 04:22:11', 15469099,
      'a=>b'::hstore, '0101000020E6100000460E6CF01988234002EA72EF86E34740'::geometry(POINT, 4326))")
    @conn.exec("SELECT OWL_UpdateWayRevisions(w.id) FROM (SELECT DISTINCT id FROM ways) w")
    verify_way_revisions
    assert_equal(10, @revisions[35345926].size)
  end

  def test_14846964
    setup_way_revisions_test(14846964)
    assert_equal(1, @revisions[203465690].size)
    assert_equal(8, @revisions[140391675].size)
  end

  def test_13018562
    setup_way_revisions_test(13018562)
  end

  def test_18915
    setup_way_revisions_test(18915)
    assert_equal(2, @revisions[14798646].size)
  end

  def test_15130053
    setup_way_revisions_test(15130053)
    @conn.exec("SELECT OWL_UpdateWayRevisions(w.id) FROM (SELECT DISTINCT id FROM ways) w")
    #assert_equal('2013-02-22 23:40:37', @revisions[42877534][-1]['tstamp'])
  end

  def test_15227387
    setup_way_revisions_test(15227387, false)
    @conn.exec("SELECT OWL_UpdateWayRevisions(68482404)")
  end

  def setup_way_revisions_test(id, update_revs = true)
    setup_db
    load_changeset(id, update_revs)
    verify_way_revisions
  end
end
