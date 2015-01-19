#!/usr/bin/env ruby

$:.unshift File.absolute_path(File.dirname(__FILE__) + '/../lib/')

# Useful when redirecting log output to a file.
STDOUT.sync = true

require 'pg'
require 'yaml'

require 'tiler/cmdline_options'
require 'tiler/logging'
require 'tiler/changeset_tiler'

GC.enable

$config = YAML.load_file(File.absolute_path(File.dirname(__FILE__) + '/../config/database.yml'))['development']
options = Tiler::parse_cmdline_options
puts options.inspect
zoom = 16
changeset_ids = ARGF.each_line.collect {|line| line.to_i}

conn = PGconn.open(:host => $config['host'], :port => $config['port'], :dbname => $config['database'],
  :user => $config['username'], :password => $config['password'])
conn.set_error_verbosity(0)
tiler = Tiler::ChangesetTiler.new(conn)

changeset_ids.each_with_index do |changeset_id, count|
  next if changeset_id == 0

  # Print out some diagnostic information.
  if count % 1000 == 0
    GC.start
    p GC::stat
    p GC::Profiler.result
    p GC::Profiler.total_time
    GC::Profiler.report
  end

  before = Time.now
  puts "Generating tiles for changeset #{changeset_id}... (#{count})"
  tile_count = tiler.generate(zoom, changeset_id, options)
  puts "Done, tile count: #{tile_count}"
  puts "Changeset #{changeset_id} took #{Time.now - before}s (#{count})"
end
