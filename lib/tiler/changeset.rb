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
    @created_at = hash['created_at'] ? Time.parse(hash['created_at']) : nil
    @closed_at = hash['closed_at'] ? Time.parse(hash['closed_at']) : nil
    @open = hash['open'] == 't'
    @tags = eval("{#{hash['tags']}}")
    @bboxes = box2d_to_bbox(hash['bboxes']) if hash['bboxes']
    @changes = Change.from_pg_array(hash['changes'])

    geojsons = pg_string_to_array(hash['geojson'])
    prev_geojsons = pg_string_to_array(hash['prev_geojson'])
    change_tags = pg_string_to_array(hash['change_tags'])
    change_prev_tags = pg_string_to_array(hash['change_prev_tags'])

    @changes.each_with_index do |change, index|
      change.geom = JSON[geojsons[index]] if geojsons[index]
      change.prev_geom = JSON[prev_geojsons[index]] if prev_geojsons[index]
      change.tags = eval("{#{change_tags[index]}}") if change_tags[index]
      change.prev_tags = eval("{#{change_prev_tags[index]}}") if change_prev_tags[index]
    end
  end

  def generate_json(options = {:include_changes => true})
    {
      "id" => id,
      "created_at" => created_at,
      "closed_at" => closed_at,
      "user_id" => user_id,
      "user_name" => user_name,
      "tags" => tags,
      #"bbox" => bbox ? box2d_to_bbox(total_bbox)[0] : nil,
      "changes" => @changes.as_json,
      "bboxes" => bboxes
    }
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
    return [] unless str
    dup = str.dup
    dup[0] = '['
    dup[-1] = ']'
    dup.gsub!('NULL', 'nil')
    eval(dup)
  end
end
