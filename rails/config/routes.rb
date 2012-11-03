OwlViewer::Application.routes.draw do
  # The priority is based upon order of creation:
  # first created -> highest priority.

  match 'changesets/:zoom/:x/:y' => 'changeset#changesets', :zoom => /\d+/, :x => /\d+/, :y => /\d+/
  match 'summary/:zoom/:x/:y' => 'changeset#summary', :zoom => /\d+/, :x => /\d+/, :y => /\d+/
end
