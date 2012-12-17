#!/usr/bin/env ruby

$:.unshift File.absolute_path(File.dirname(__FILE__) + '/../tiler/lib/')

# Useful when redirecting log output to a file.
STDOUT.sync = true

require 'pg'
require 'yaml'

require 'cmdline_options'
require 'logging'
require 'tiler'

$config = YAML.load_file('../rails/config/database.yml')['development']

options = Tiler::parse_cmdline_options

puts options.inspect

@conn = PGconn.open(:host => $config['host'], :port => $config['port'], :dbname => $config['database'],
  :user => $config['username'], :password => $config['password'])

tiler = Tiler::Tiler.new(@conn)

zoom = 16
count = 0

ARGF.each_line do |line|
  changeset_id = line.to_i
  next if changeset_id == 0
  count += 1
  before = Time.now
  puts "Generating tiles for changeset #{changeset_id}... (#{count})"
  tile_count = tiler.generate(zoom, changeset_id, options)
  puts "Done, tile count: #{tile_count}"
  puts "Changeset #{changeset_id} took #{Time.now - before}s (#{count})"
end
