#!/usr/bin/env ruby

STDOUT.sync = true

require 'pg'
require 'yaml'

LIMIT = 10000

$config = YAML.load_file('../rails/config/database.yml')['development']

@conn = PGconn.open(:host => $config['host'], :port => $config['port'], :dbname => $config['database'],
  :user => $config['username'], :password => $config['password'])

i = 0
@conn.exec("SELECT DISTINCT id FROM ways").to_a.each_slice(LIMIT) do |ids|
  @conn.transaction do |c|
    for id in ids.collect {|row| row['id'].to_i}
      @conn.exec("SELECT OWL_CreateWayRevisions(#{id})")
    end
  end
  puts LIMIT * (i + 1)
  i += 1
end
