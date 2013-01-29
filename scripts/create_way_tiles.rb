#!/usr/bin/env ruby

$:.unshift File.absolute_path(File.dirname(__FILE__) + '/../tiler/lib/')

STDOUT.sync = true

require 'pg'
require 'yaml'
require 'way_tiler'

LIMIT = 10000

$config = YAML.load_file('../rails/config/database.yml')['development']

@conn = PGconn.open(:host => $config['host'], :port => $config['port'], :dbname => $config['database'],
  :user => $config['username'], :password => $config['password'])

@way_tiler = ::Tiler::WayTiler.new(@conn)

i = 0
@conn.exec("SELECT DISTINCT id FROM ways").to_a.each_slice(LIMIT) do |ids|
  @conn.transaction do |c|
    for id in ids.collect {|row| row['id'].to_i}
      @way_tiler.create_way_tiles(id)
    end
  end
  puts LIMIT * (i + 1)
  i += 1
end
