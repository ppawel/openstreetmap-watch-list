OwlViewer::Application.routes.draw do
  @xyz_constraints = {:zoom => /\d+/, :x => /\d+/, :y => /\d+/}
  @range_constraints = {:zoom => /\d+/, :x1 => /\d+/, :y1 => /\d+/, :x2 => /\d+/, :y2 => /\d+/}

  # The priority is based upon order of creation:
  # first created -> highest priority.

  # Tile operations
  match 'api/0.1/changesets/:zoom/:x/:y.atom' => 'api#changesets_tile_atom', :constraints => @xyz_constrains, :format => 'atom'
  match 'api/0.1/changesets/:zoom/:x/:y.geojson' => 'api#changesets_tile_geojson', :constraints => @xyz_constrains, :format => 'json'
  match 'api/0.1/changesets/:zoom/:x/:y.json' => 'api#changesets_tile_json', :constraints => @xyz_constrains, :format => 'json'

  # Tile range operations
  match 'api/0.1/changesets/:zoom/:x1/:y1/:x2/:y2.atom' => 'api#changesets_tilerange_atom', :constraints => @range_constrains, :format => 'atom'
  match 'api/0.1/changesets/:zoom/:x1/:y1/:x2/:y2.geojson' => 'api#changesets_tilerange_geojson', :constraints => @range_constrains, :format => 'json'
  match 'api/0.1/changesets/:zoom/:x1/:y1/:x2/:y2.json' => 'api#changesets_tilerange_json', :constraints => @range_constrains, :format => 'json'

  match 'api/0.1/summary/:zoom/:x/:y' => 'api#summary_tile', :constraints => @xyz_constrains
  match 'api/0.1/summary/:zoom/:x1/:y1/:x2/:y2' => 'api#summary_tilerange', :constraints => @range_constrains, :format => 'json'
end
