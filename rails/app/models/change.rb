require 'ffi-geos'

class Change
  attr_accessor :id
  attr_accessor :changeset_id
  attr_accessor :tstamp
  attr_accessor :el_type
  attr_accessor :el_id
  attr_accessor :el_version
  attr_accessor :el_action
  attr_accessor :geom_changed
  attr_accessor :tags_changed
  attr_accessor :nodes_changed
  attr_accessor :members_changed
  attr_accessor :geom_geojson
  attr_accessor :prev_geom_geojson
  attr_accessor :tags
  attr_accessor :prev_tags
  attr_accessor :nodes
  attr_accessor :prev_nodes
  attr_accessor :origin_el_type
  attr_accessor :origin_el_id
  attr_accessor :origin_el_version
  attr_accessor :origin_el_action

  def self.from_string(changeset_id, str)
    hash = {}
    a = str.delete('(', ')').split(',')
    hash['id'] = a[0]
    hash['tstamp'] = a[1].delete('"')
    hash['el_type'] = a[2]
    hash['el_action'] = a[3]
    hash['el_id'] = a[4]
    hash['el_version'] = a[5]
    #hash['geom_geojson'] = geojson(a[-2]) unless a[-2].empty?
    #hash['prev_geom_geojson'] = geojson(a[-1]) unless a[-1].empty?
    Change.new(changeset_id, hash)
  end

  def self.geojson(wkb)
    wkb_reader = Geos::WkbReader.new
    geom = wkb_reader.read_hex(wkb)
    geom.json
  end

  def initialize(changeset_id, hash)
    @id = hash['id'].to_i
    @changeset_id = changeset_id
    @tstamp = Time.parse(hash['tstamp'])
    @el_type = hash['el_type']
    @el_id = hash['el_id'].to_i
    @el_version = hash['el_version'].to_i
    @el_action = hash['el_action']
    @geom_changed = hash['geom_changed'] == 't' if hash['geom_changed']
    @tags_changed = hash['tags_changed'] == 't' if hash['tags_changed']
    @nodes_changed = hash['nodes_changed'] == 't' if hash['nodes_changed']
    @members_changed = hash['members_changed'] == 't' if hash['members_changed']
    @tags = eval("{#{hash['tags']}}")
    @prev_tags = eval("{#{hash['prev_tags']}}") if hash['prev_tags']
    @geom_geojson = hash['geom_geojson']
    @prev_geom_geojson = hash['prev_geom_geojson']
  end

  def as_json(options = {})
    Hash[instance_variables.collect {|key| [key.to_s.gsub('@', ''), instance_variable_get(key)]}]
  end
end
