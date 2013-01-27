$:.unshift File.absolute_path(File.dirname(__FILE__)) + '/../lib'

require 'pg'
require 'test/unit'
require 'yaml'
require 'tiler'

require './common'

class WaySubversionsTest < Test::Unit::TestCase
  include TestCommon

  def test_13294164
    setup_way_revisions_test(13294164)
  end

  def setup_way_revisions_test(id)
    setup_db
    load_changeset(13294164)
    @conn.exec("SELECT OWL_CreateWaySubversions(w.id) FROM (SELECT DISTINCT id FROM ways) w")
    @subversions = {}
    for sub in @conn.exec("SELECT * FROM way_revisions ORDER BY way_id, way_version, subversion").to_a
      @subversions[sub['way_id']] ||= []
      @subversions[sub['way_id']] << sub
    end
    verify_subversions
  end

  def verify_subversions
    for way_subs in @subversions.values
      way_subs.each_cons(2) do |sub_pair|
        assert(sub_pair[0]['tstamp'] < sub_pair[1]['tstamp'], "Newer subversion has older or equal timestamp: #{sub_pair}")
      end
    end
  end
end
