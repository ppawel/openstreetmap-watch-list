#!/usr/bin/env ruby

require 'pg'
require 'yaml'

$config = YAML.load_file('../rails/config/database.yml')['development']

@conn = PGconn.open(:host => $config['host'], :port => $config['port'], :dbname => $config['database'],
  :user => $config['username'], :password => $config['password'])
@conn.prepare('create', 'SELECT OWL_CreateWayRevisions($1)')

way_ids = ARGF.each_line.collect {|line| line.to_i}

way_ids.each_with_index do |way_id, count|
  @conn.exec_prepared('create', [way_id])
  puts "#{way_id} (#{count} / #{way_ids.size})"
end
