$:.unshift File.absolute_path(File.dirname(__FILE__)) + '/../lib'

require 'pg'
require 'test/unit'
require 'yaml'
require 'tiler'

require './common'

class WayRevisionsTest < Test::Unit::TestCase
  include TestCommon

  def test_13294164
    setup_way_revisions_test(13294164)
  end

  def setup_way_revisions_test(id)
    setup_db
    load_changeset(13294164)
    @revisions = {}
    for sub in @conn.exec("SELECT * FROM way_revisions ORDER BY way_id, way_version, revision").to_a
      @revisions[sub['way_id']] ||= []
      @revisions[sub['way_id']] << sub
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
