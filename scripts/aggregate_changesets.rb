#!/usr/bin/env ruby

STDOUT.sync = true

require 'pg'
require 'yaml'

$config = YAML.load_file('../rails/config/database.yml')['development']

@conn = PGconn.open(:host => $config['host'], :port => $config['port'], :dbname => $config['database'],
  :user => $config['username'], :password => $config['password'])

changesets = @conn.query("SELECT id FROM changesets").to_a

changesets.each_with_index do |row, index|
  puts "#{Time.now} - Changeset #{row['id']} (#{index + 1} / #{changesets.size})"

  (3..16).reverse_each do |i|
    @conn.query("SELECT OWL_AggregateChangeset(#{row['id']}, #{i}, #{i - 1})")
  end
end
