class Changeset
  def entity_changes_as_list
    entity_changes.gsub('{', '').gsub('}', '').split(',').map(&:to_i)
  end

  def as_json(options = {})
    result = {
      "id" => id,
      "created_at" => created_at,
      "closed_at" => closed_at,
      "user_id" => user_id,
      "user_name" => user_name,
      "entity_changes" => entity_changes.nil? ? [] : entity_changes_as_list,
      "tags" => eval("{#{tags}}"),
      "bbox" => bbox ? box2d_to_bbox(total_bbox)[0] : nil,
      "changes" => changes.to_s
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
