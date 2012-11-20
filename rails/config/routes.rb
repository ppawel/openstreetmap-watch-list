OwlViewer::Application.routes.draw do
  @xyz_constraints = {:zoom => /\d+/, :x => /\d+/, :y => /\d+/}

  # The priority is based upon order of creation:
  # first created -> highest priority.

  match 'changesets/:zoom/:x/:y.atom' => 'api#changesets_tile_atom', :constraints => @xyz_constrains, :format => 'atom'
  match 'changesets/:zoom/:x/:y.geojson' => 'api#changesets_tile_geojson', :constraints => @xyz_constrains, :format => 'json'
  match 'changesets/:zoom/:x/:y.json' => 'api#changesets_tile_json', :constraints => @xyz_constrains, :format => 'json'
  match 'summary/:zoom/:x/:y' => 'api#summary', :constraints => @xyz_constrains
end
