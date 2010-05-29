ActionController::Routing::Routes.draw do |map|
  map.connect "map", :controller => "changeset", :action => "map"
  map.connect "map.:format", :controller => "changeset", :action => "map"
  map.connect "dailymap", :controller => "changeset", :action => "dailymap"
  map.connect "dailymap.:format", :controller => "changeset", :action => "dailymap"
  map.connect "weeklymap", :controller => "changeset", :action => "weeklymap"
  map.connect "weeklymap.:format", :controller => "changeset", :action => "weeklymap"
  map.connect "tile/:id", :controller => "changeset", :action => "tile", :id => /\d+/
  map.connect "tiles/:id", :controller => "changeset", :action => "tiles", :id => /\d+/
  map.connect "tiles/:id.:format", :controller => "changeset", :action => "tiles", :id => /\d+/
  map.connect "feed/:range.:format", :controller => "changeset", :action => "feed", :range => /\d+(-\d+)?(,\d+(-\d+)?)*/
end
