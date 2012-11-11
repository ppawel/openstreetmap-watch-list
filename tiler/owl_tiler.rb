#!/usr/bin/env ruby

STDOUT.sync = true

$:.unshift File.absolute_path(File.dirname(__FILE__) + '/lib/')

require 'pg'
require 'parallel'
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

changeset_ids = tiler.get_changeset_ids(options)
zoom = options[:zoom_level]
count = 0

puts "Changesets to process: #{changeset_ids.size}"

changeset_ids.each do |changeset_id|
  count += 1
  before = Time.now

  @conn.transaction do |c|
    puts "Generating tiles for changeset #{changeset_id}... (#{count} of #{changeset_ids.size})"
    tiler.clear_tiles(changeset_id, zoom) if options[:retile]
    tile_count = tiler.generate(zoom, changeset_id, options)
    puts "Done, tile count: #{tile_count}"
  end

  puts "Changeset #{changeset_id} took #{Time.now - before}s (#{count} of #{changeset_ids.size})"
end
