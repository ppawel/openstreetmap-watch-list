#!/usr/bin/env ruby

$:.unshift File.absolute_path(File.dirname(__FILE__) + '/lib/')

require 'optparse'
require 'pg'
require 'yaml'

require 'logging'
require 'tiler'

$config = YAML.load_file('../rails/config/database.yml')['development']

options = {}

opt = OptionParser.new do |opts|
  opts.banner = "Usage: owl_tiler.rb [options]"

  opts.separator('')

  opts.on("--changesets <value>", String,
      "List of changesets; possible values for this option:",
      "all - all changesets from the database",
      "Default is 'all'.") do |c|
    options[:changesets] = c
  end

  opts.separator('')

  opts.on("--zoom x,y,z", Array, "Comma-separated list of zoom levels, e.g. 4,5,6") do |list|
    options[:zoom] = list.map(&:to_i)
  end

  opts.separator('')

  opts.on("--retile", "Remove existing tiles and regenerate tiles from scratch (optional, default is false)") do |o|
    options[:retile] = o
  end
end

opt.parse!

options[:changesets] ||= 'all'

if !options[:zoom] or !options[:changesets]
  puts opt.help
  exit 1
end

@conn = PGconn.open(:host => $config['host'], :port => $config['port'], :dbname => $config['database'],
  :user => $config['username'], :password => $config['password'])

tiler = Tiler::Tiler.new(@conn)

for zoom in options[:zoom]
  @conn.query("SELECT id FROM changesets ORDER BY created_at DESC").each do |row|
    before = Time.now
    changeset_id = row['id'].to_i

    @conn.transaction do |c|
      puts "Generating tiles for changeset #{changeset_id} at zoom level #{zoom}..."
      tile_count = tiler.generate(zoom, changeset_id, options)
      puts "Done, tile count: #{tile_count}"
    end

    puts "Changeset #{changeset_id} took #{Time.now - before}ms"
  end
end
