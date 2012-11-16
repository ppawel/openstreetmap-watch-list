class SummaryTile < ActiveRecord::Base
  belongs_to :latest_changeset, :class_name => 'Changeset'
  attr_accessible :num_changesets

  def as_json(options)
    {
      "num_changesets" => num_changesets,
      "latest_changeset" => latest_changeset ? latest_changeset.as_json(options) : nil
    }
  end
end
