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

  def entity_changes_as_list
    entity_changes.gsub('{', '').gsub('}', '').split(',').map(&:to_i)
  end

  def as_json(options)
    {
      "id" => id,
      "created_at" => created_at,
      "closed_at" => closed_at,
      "user_id" => user.id,
      "user_name" => user.name,
      "entity_changes" => entity_changes_as_list,
      "tags" => tags
    }
  end
end
