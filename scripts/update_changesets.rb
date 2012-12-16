#!/usr/bin/env ruby

STDOUT.sync = true

require 'pg'
require 'yaml'

$config = YAML.load_file('../rails/config/database.yml')['development']

@conn = PGconn.open(:host => $config['host'], :port => $config['port'], :dbname => $config['database'],
  :user => $config['username'], :password => $config['password'])

changesets = @conn.query("SELECT DISTINCT changeset_id FROM nodes").to_a

changesets.each_with_index do |row, index|
  puts "#{Time.now} - Changeset #{row['id']} (#{index + 1} / #{changesets.size})"
  @conn.query("SELECT OWL_GenerateChanges(#{row['changeset_id']})")
end
