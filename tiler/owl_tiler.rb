#!/usr/bin/env ruby

STDOUT.sync = true

$:.unshift File.absolute_path(File.dirname(__FILE__) + '/lib/')

require 'pg'
require 'yaml'

require 'cmdline_options'
require 'logging'
require 'tiler'

$config = YAML.load_file('../rails/config/database.yml')['development']

def get_changeset_ids(tiler, options)
  if options[:file]
    return File.open(options[:file]).each_line.collect {|line| line.to_i}
  else
    return tiler.get_changeset_ids(options)
  end
end

options = Tiler::parse_cmdline_options

puts options.inspect

@conn = PGconn.open(:host => $config['host'], :port => $config['port'], :dbname => $config['database'],
  :user => $config['username'], :password => $config['password'])

tiler = Tiler::Tiler.new(@conn)

changeset_ids = get_changeset_ids(tiler, options)
zoom = options[:zoom_level]
count = 0

puts "Changesets to process: #{changeset_ids.size}"

changeset_ids.each do |changeset_id|
  count += 1
  before = Time.now

  puts "Generating tiles for changeset #{changeset_id}... (#{count} of #{changeset_ids.size})"
  tile_count = tiler.generate(zoom, changeset_id, options)
  puts "Done, tile count: #{tile_count}"

  puts "Changeset #{changeset_id} took #{Time.now - before}s (#{count} of #{changeset_ids.size})"
end
