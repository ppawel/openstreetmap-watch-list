OwlViewer::Application.routes.draw do
  # The priority is based upon order of creation:
  # first created -> highest priority.

  match 'map'                    => 'changeset#map'
  match 'changesets.:format'     => 'changeset#changesets'
  match 'changesets/:zoom/:x/:y' => 'changeset#tile', :zoom => /\d+/, :x => /\d+/, :y => /\d+/
end
