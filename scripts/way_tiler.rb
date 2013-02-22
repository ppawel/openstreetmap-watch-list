#!/usr/bin/env ruby

$:.unshift File.absolute_path(File.dirname(__FILE__) + '/../tiler/lib/')

require 'pg'
require 'yaml'
require 'way_tiler'

$config = YAML.load_file('../rails/config/database.yml')['development']

@conn = PGconn.open(:host => $config['host'], :port => $config['port'], :dbname => $config['database'],
  :user => $config['username'], :password => $config['password'])

@way_tiler = ::Tiler::WayTiler.new(@conn)

i = 0
ARGF.each_line do |way_id|
  @conn.transaction do |c|
    @way_tiler.create_way_tiles(way_id.to_i)
  end
  i += 1
  puts "---- #{i}" if i % 1000
end
