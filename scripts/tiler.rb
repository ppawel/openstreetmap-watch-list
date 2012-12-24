#!/usr/bin/env ruby

$:.unshift File.absolute_path(File.dirname(__FILE__) + '/../tiler/lib/')

# Useful when redirecting log output to a file.
STDOUT.sync = true

require 'parallel'
require 'pg'
require 'yaml'

require 'cmdline_options'
require 'logging'
require 'tiler'

$config = YAML.load_file('../rails/config/database.yml')['development']

options = Tiler::parse_cmdline_options

puts options.inspect

zoom = 16

changeset_ids = ARGF.each_line.collect {|line| line.to_i}

Parallel.each_with_index(changeset_ids, :in_processes => 8) do |changeset_id, count|
  next if changeset_id == 0

  @conn = PGconn.open(:host => $config['host'], :port => $config['port'], :dbname => $config['database'],
    :user => $config['username'], :password => $config['password'])
  tiler = Tiler::Tiler.new(@conn)

  before = Time.now
  puts "Generating tiles for changeset #{changeset_id}... (#{count})"
  tile_count = tiler.generate(zoom, changeset_id, options)
  puts "Done, tile count: #{tile_count}"
  puts "Changeset #{changeset_id} took #{Time.now - before}s (#{count})"
end
