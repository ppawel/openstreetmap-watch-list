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
    @conn.exec("INSERT INTO nodes VALUES (414458276, 5, 5, true, true, 1679, '2012-12-31 03:22:11', 14469098,
      'a=>b'::hstore, '0101000020E6100000FEAE192A10C753C0BE7273E08BE74540'::geometry)")
    @conn.exec("SELECT OWL_CreateWayRevisions(w.id, true) FROM (SELECT DISTINCT id FROM ways) w")
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

  def setup_way_revisions_test(id)
    setup_db
    load_changeset(id)
    verify_revisions
    @conn.exec("SELECT OWL_CreateWayRevisions(w.id, true) FROM (SELECT DISTINCT id FROM ways) w")
  end

  def verify_revisions
    verify_way_revisions

    @revisions = {}
    for rev in @conn.exec("SELECT rev.*, OWL_MakeLine(w.nodes, rev.tstamp) AS geom, w.tags
        FROM way_revisions rev
        INNER JOIN ways w ON (w.id = rev.way_id AND w.version = rev.version)
        ORDER BY way_id, rev.version, rev.rev").to_a
      @revisions[rev['way_id'].to_i] ||= []
      @revisions[rev['way_id'].to_i] << rev
    end

    for revs in @revisions.values
      for rev in revs
        #p rev
      end
    end

    for way_subs in @revisions.values
      way_subs.each_cons(2) do |sub_pair|
        assert(sub_pair[0]['tstamp'] < sub_pair[1]['tstamp'], "Newer revision has older or equal timestamp: #{sub_pair}")
        assert(((sub_pair[0]['geom'] != sub_pair[1]['geom']) or (sub_pair[0]['tags'] != sub_pair[1]['tags']) \
          or (sub_pair[0]['nodes'] != sub_pair[0]['prev_nodes']) or (sub_pair[0]['version'].to_i < sub_pair[1]['version'].to_i)),
          "Revision is not different from previous one: #{sub_pair}")
      end
    end
  end
end
