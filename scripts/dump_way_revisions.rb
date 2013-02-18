#!/usr/bin/env ruby

require 'pg'
require 'yaml'

$config = YAML.load_file('../rails/config/database.yml')['development']

@conn = PGconn.open(:host => $config['host'], :port => $config['port'], :dbname => $config['database'],
  :user => $config['username'], :password => $config['password'])

ARGF.each_line do |way_id|
  @conn.exec("COPY (SELECT * FROM OWL_CreateWayRevisions(#{way_id}, true)) TO STDOUT")
  while not (data = @conn.get_copy_data).nil?
    puts data
  end
end
