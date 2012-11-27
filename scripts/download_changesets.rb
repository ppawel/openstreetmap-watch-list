#!/usr/bin/env ruby

STDOUT.sync = true

require 'nokogiri'
require 'open-uri'
require 'pg'
require 'yaml'

def parse_tags(changeset_el)
  tags = {}
  changeset_el.children.each do |tag_el|
    next unless tag_el.element?
    tags[tag_el['k']] = tag_el['v']
  end
  tags
end

if ARGV.size == 0
  puts "Usage: download_changesets.rb <file_id>"
  puts ""
  puts "Example: download_changesets.rb 000023332"
  exit
end

file_id = ARGV[0]

$config = YAML.load_file('../rails/config/database.yml')['development']

@conn = PGconn.open(:host => $config['host'], :port => $config['port'], :dbname => $config['database'],
  :user => $config['username'], :password => $config['password'])

@conn.transaction do |c|
  open("http://planet.openstreetmap.org/replication/changesets/#{file_id[0..2]}/#{file_id[3..5]}/#{file_id[6..8]}.osm.gz") do |f|
    gz = Zlib::GzipReader.new(f)
    text = gz.read
    puts text
    xml = Nokogiri::XML(text)
    xml.root.children.each do |changeset_el|
      next unless changeset_el.element?
      id = changeset_el['id'].to_i
      print "Processing changeset #{id}... "
      print @conn.exec("
        UPDATE changesets
        SET
          closed_at = #{!changeset_el['closed_at'] ? 'NULL' : '\'' + changeset_el['closed_at'] + '\''},
          tags = '#{PGconn.escape(parse_tags(changeset_el).to_s.gsub('{', '').gsub('}', ''))}'::hstore
        WHERE id = #{id}").cmd_tuples
      puts
    end
  end
end
