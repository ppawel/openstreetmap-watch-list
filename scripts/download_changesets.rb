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

def update_changeset(changeset_el)
  id = changeset_el['id'].to_i
  count = @conn.exec("
    UPDATE changesets
    SET
      closed_at = #{!changeset_el['closed_at'] ? 'NULL' : '\'' + changeset_el['closed_at'] + '\''},
      tags = '#{PGconn.escape(parse_tags(changeset_el).to_s.gsub('{', '').gsub('}', ''))}'::hstore
    WHERE id = #{id}").cmd_tuples
end

def save_state(state)
  File.open('state.yaml', 'w') {|f| f.puts(state.to_yaml)}
end

$config = YAML.load_file('../rails/config/database.yml')['development']
current_state = YAML.load_file('state.yaml')
remote_state = YAML.load(open('http://planet.openstreetmap.org/replication/changesets/state.yaml').read)

@conn = PGconn.open(:host => $config['host'], :port => $config['port'], :dbname => $config['database'],
  :user => $config['username'], :password => $config['password'])

for id in (current_state['sequence'].to_i + 1..remote_state['sequence'].to_i)
  file_id = id.to_s.rjust(9, '0')
  puts "file_id = #{file_id}"

  begin
    @conn.transaction do |c|
      open("http://planet.openstreetmap.org/replication/changesets/#{file_id[0..2]}/#{file_id[3..5]}/#{file_id[6..8]}.osm.gz") do |f|
        next if f.size == 0
        gz = Zlib::GzipReader.new(f)
        text = gz.read
        puts text
        xml = Nokogiri::XML(text)
        xml.root.children.each do |changeset_el|
          next unless changeset_el.element?
          changeset_id = changeset_el['id'].to_i
          print "Processing changeset #{changeset_id}... "
          count = update_changeset(changeset_el)
          puts "#{count}, open = #{changeset_el['open']}, has_bbox = #{!changeset_el['min_lat'].nil?}"

          if count == 0 and changeset_el['open'] == 'false' and changeset_el['min_lat']
            puts ' Not in the database, stopping...'
            raise
          end
        end
      end
    end

    current_state['sequence'] = id
    save_state(current_state)
  rescue
    puts $!.inspect, $@
    exit
  end
end
