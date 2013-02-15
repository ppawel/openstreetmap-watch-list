#!/usr/bin/env ruby

STDOUT.sync = true

require 'pg'
require 'yaml'

LIMIT = 10000

$config = YAML.load_file('../rails/config/database.yml')['development']

@conn = PGconn.open(:host => $config['host'], :port => $config['port'], :dbname => $config['database'],
  :user => $config['username'], :password => $config['password'])

i = 0
while true do
  @conn.exec("SELECT OWL_CreateWayRevisions(id) FROM ways ORDER BY id DESC LIMIT #{LIMIT} OFFSET #{i * LIMIT} ")
  i += 1
  puts "---- #{LIMIT * i}"
end
