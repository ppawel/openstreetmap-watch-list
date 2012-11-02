#!/usr/bin/env ruby

require 'optparse'
require 'pg'

require './scripts/tilerlib'

$config = {
  'host' => 'localhost',
  'port' => 5432,
  'dbname' => 'osmdb',
  'user' => 'ppawel',
  'password' => 'aa'
}

options = {}

opt = OptionParser.new do |opts|
  opts.banner = "Usage: owl_tiler.rb [options]"

  opts.separator('')

  opts.on("--changesets <value>", String,
      "List of changesets; possible values for this option:",
      "all - all changesets from the database",
      "<n> - number of last changesets to consider") do |c|
    options[:changesets] = c
  end

  opts.separator('')

  opts.on("--zoom x,y,z", Array, "Comma-separated list of zoom levels, e.g. 4,5,6") do |list|
    options[:zoom] = list.map(&:to_i)
  end
end

if !options[:zoom] or !options[:changesets]
  puts opt.help
  exit 1
end

@conn = PGconn.open(:host => $config['host'], :port => $config['port'], :dbname => $config['dbname'], :user => $config['user'], :password => $config['password'])

tiler = Tiler.new(@conn)

for zoom in options[:zoom]
  @conn.query("SELECT id FROM changesets ORDER BY created_at DESC LIMIT 10").each do |row|
    @conn.transaction do |c|
      changeset_id = row['id'].to_i
      puts "Generating tiles for changeset #{changeset_id} at zoom level #{zoom}..."
      tile_count = tiler.generate(zoom, changeset_id)
      puts "Done, tile count: #{tile_count}"
    end
  end
end
