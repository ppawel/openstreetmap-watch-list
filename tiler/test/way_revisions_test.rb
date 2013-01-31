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
    p @revisions
    assert_equal(7, @revisions[35345926].size)
  end

  def setup_way_revisions_test(id)
    setup_db
    load_changeset(id)
    @revisions = {}
    for sub in @conn.exec("SELECT * FROM way_revisions ORDER BY way_id, way_version, revision").to_a
      @revisions[sub['way_id'].to_i] ||= []
      @revisions[sub['way_id'].to_i] << sub
    end
    verify_revisions
  end

  def verify_revisions
    for way_subs in @revisions.values
      way_subs.each_cons(2) do |sub_pair|
        assert(sub_pair[0]['tstamp'] < sub_pair[1]['tstamp'], "Newer revision has older or equal timestamp: #{sub_pair}")
      end
    end
  end
end
