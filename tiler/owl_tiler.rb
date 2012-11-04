#!/usr/bin/env ruby

$:.unshift File.absolute_path(File.dirname(__FILE__) + '/lib/')

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

for summary_zoom in options[:summary_tiles]
  before = Time.now

  @conn.transaction do |c|
    puts "Generating summary tiles for zoom level #{summary_zoom}..."
    tiler.generate_summary_tiles(summary_zoom)
  end

  puts "Took #{Time.now - before}s"
end

changeset_ids = tiler.get_changeset_ids(options)

for zoom in options[:geometry_tiles]
  count = 0
  puts "Changesets to process: #{changeset_ids.size}"
  changeset_ids.each do |changeset_id|
    count += 1
    before = Time.now

    @conn.transaction do |c|
      puts "Generating tiles for changeset #{changeset_id} at zoom level #{zoom}... (#{count} of #{changeset_ids.size})"

      if options[:retile]
        removed_count = tiler.clear_tiles(changeset_id, zoom)
        puts "Removed existing tiles: #{removed_count}"
      end

      tile_count = tiler.generate(zoom, changeset_id, options)
      tiler.update_tiled_at(changeset_id)
      puts "Done, tile count: #{tile_count}"
    end

    puts "Changeset #{changeset_id} took #{Time.now - before}s (#{count} of #{changeset_ids.size})"
  end
end
