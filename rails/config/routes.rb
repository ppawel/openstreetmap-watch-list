OwlViewer::Application.routes.draw do
  # The priority is based upon order of creation:
  # first created -> highest priority.

  match 'changesets/:zoom/:x/:y' => 'api#changesets', :zoom => /\d+/, :x => /\d+/, :y => /\d+/
  match 'summary/:zoom/:x/:y' => 'api#summary', :zoom => /\d+/, :x => /\d+/, :y => /\d+/
end
