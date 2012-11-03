class SummaryTile < ActiveRecord::Base
  def to_json(x)
    ['num_changesets' => num_changesets]
  end
end
