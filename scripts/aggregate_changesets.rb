#!/usr/bin/env ruby

STDOUT.sync = true

require 'pg'
require 'yaml'

$config = YAML.load_file('../rails/config/database.yml')['development']

@conn = PGconn.open(:host => $config['host'], :port => $config['port'], :dbname => $config['database'],
  :user => $config['username'], :password => $config['password'])

count = 0

ARGF.each_line do |line|
  changeset_id = line.to_i
  next if changeset_id == 0
  puts "Aggregating changeset #{changeset_id}... (#{count})"
  @conn.transaction do |c|
    (3..16).reverse_each do |i|
      @conn.query("SELECT OWL_AggregateChangeset(#{changeset_id}, #{i}, #{i - 1})")
    end
  end
end
