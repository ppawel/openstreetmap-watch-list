class Changeset < ActiveRecord::Base
  belongs_to :user
  attr_accessible :id
  attr_accessible :user_id
  attr_accessible :created_at
  attr_accessible :closed_at
  attr_accessible :last_tiled_at
  attr_accessible :tags
  attr_accessible :entity_changes
  attr_accessible :bbox
  attr_accessible :geojson
  attr_accessible :tile_bbox
  attr_accessible :tile_bboxes

  def entity_changes_as_list
    entity_changes.gsub('{', '').gsub('}', '').split(',').map(&:to_i)
  end

  def as_json(options = {})
    result = {
      "id" => id,
      "created_at" => created_at,
      "closed_at" => closed_at,
      "user_id" => user.id,
      "user_name" => user.name,
      "entity_changes" => entity_changes_as_list,
      "tags" => eval("{#{tags}}"),
      "bbox" => bbox ? box2d_to_bbox(total_bbox)[0] : nil,
    }
    if has_attribute?('tile_bbox')
      boxes = box2d_to_bbox(tile_bbox)
      result['tile_bbox'] = boxes[0]
    end
    if has_attribute?('tile_bboxes')
      boxes = box2d_to_bbox(tile_bboxes)
      result['tile_bboxes'] = boxes
    end
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
end
