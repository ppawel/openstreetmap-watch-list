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
  end

  def setup_way_revisions_test(id)
    setup_db
    load_changeset(id)
    verify_revisions
  end

  def verify_revisions
    @revisions = {}
    for sub in @conn.exec("SELECT rev.*, OWL_MakeLine(w.nodes, rev.tstamp) AS geom, w.tags
        FROM way_revisions rev
        INNER JOIN ways w ON (w.id = rev.way_id AND w.version = rev.version)
        ORDER BY way_id, rev.version, rev.rev").to_a
      @revisions[sub['way_id'].to_i] ||= []
      @revisions[sub['way_id'].to_i] << sub
    end

    for way_subs in @revisions.values
      way_subs.each_cons(2) do |sub_pair|
        assert(sub_pair[0]['tstamp'] < sub_pair[1]['tstamp'], "Newer revision has older or equal timestamp: #{sub_pair}")
        assert(((sub_pair[0]['geom'] != sub_pair[1]['geom']) or (sub_pair[0]['tags'] != sub_pair[1]['tags']) \
          or (sub_pair[0]['nodes'] != sub_pair[0]['prev_nodes'])), "Revision is not different from previous one: #{sub_pair}")
      end
    end
  end
end
