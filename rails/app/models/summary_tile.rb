class SummaryTile < ActiveRecord::Base
  def as_json(x)
    {'num_changesets' => num_changesets}
  end
end
