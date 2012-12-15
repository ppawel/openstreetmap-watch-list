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
  attr_accessor :tags
  attr_accessor :prev_tags
  attr_accessor :nodes
  attr_accessor :prev_nodes
  attr_accessor :origin_el_type
  attr_accessor :origin_el_id
  attr_accessor :origin_el_version
  attr_accessor :origin_el_action

  def initialize(hash)
    @id = hash['id'].to_i
    @changeset_id = hash['changeset_id'].to_i
    @tstamp = Date.parse(hash['tstamp'])
    @tags = eval("{#{hash['tags']}}")
    @prev_tags = eval("{#{hash['prev_tags']}}") if hash['prev_tags']
    @geom_changed = hash['geom_changed'] == 't' if hash['geom_changed']
    @tags_changed = hash['tags_changed'] == 't' if hash['tags_changed']
    @nodes_changed = hash['nodes_changed'] == 't' if hash['nodes_changed']
    @members_changed = hash['members_changed'] == 't' if hash['members_changed']
  end

  def as_json(options = {})
    Hash[instance_variables.collect {|key| [key.to_s.gsub('@', ''), instance_variable_get(key)]}]
  end
end
