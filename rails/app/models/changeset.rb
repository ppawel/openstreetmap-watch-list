class Changeset
  attr_accessor :id
  attr_accessor :user_id
  attr_accessor :user_name
  attr_accessor :created_at
  attr_accessor :closed_at
  attr_accessor :open
  attr_accessor :tags
  attr_accessor :entity_changes
  attr_accessor :num_changes
  attr_accessor :change_ids
  attr_accessor :bboxes
  attr_accessor :changes
  attr_accessor :geom_geojson
  attr_accessor :prev_geom_geojson

  def initialize(hash)
    @id = hash['id'].to_i
    @user_id = hash['user_id'].to_i
    @user_name = hash['user_name']
    @created_at = Time.parse(hash['created_at'])
    @closed_at = Time.parse(hash['closed_at'])
    @open = hash['open'] == 't'
    @tags = eval("{#{hash['tags']}}")
    @change_ids = pg_string_to_array(hash['change_ids']).map(&:to_i) if hash['change_ids']
    @bboxes = box2d_to_bbox(hash['bboxes']) if hash['bboxes']
    @geom_geojson = pg_string_to_array(hash['geom_geojson']) if hash['geom_geojson']
    @prev_geom_geojson = pg_string_to_array(hash['prev_geom_geojson']) if hash['prev_geom_geojson']
  end

  def generate_json(options = {:include_changes => true})
    result = {
      "id" => id,
      "created_at" => created_at,
      "closed_at" => closed_at,
      "user_id" => user_id,
      "user_name" => user_name,
      #"entity_changes" => entity_changes.nil? ? [] : entity_changes_as_list,
      "tags" => tags,
      #"bbox" => bbox ? box2d_to_bbox(total_bbox)[0] : nil,
      "bboxes" => bboxes
    }
    result['changes'] = changes || [] if options[:include_changes]
    result
  end

  ##
  # Converts PostGIS' BOX2D string representation to a list.
  # bbox is [xmin, ymin, xmax, ymax]
  #
  def box2d_to_bbox(box2d)
    return [] if !box2d
    result = []
    box2d.scan(/BOX\(([\d\.]+) ([\d\.]+),([\d\.]+) ([\d\.]+)\)/).each do |m|
      result << m.map(&:to_f)
    end
    result.uniq
  end

  def pg_string_to_array(str)
    dup = str.dup
    dup[0] = '['
    dup[-1] = ']'
    dup.gsub!('NULL', 'nil')
    eval(dup)
  end
end
