require 'pg'
require './tiler'

if ARGV.size != 2
  puts "Usage: generate_tiles.rb <zoom level> <limit> [offset]"
  exit
end

ZOOM_LEVEL = ARGV[0].to_i
LIMIT = ARGV[1].to_i
OFFSET = ARGV[2].to_i || 100

$config = {
  'host' => 'localhost',
  'port' => 5432,
  'dbname' => 'osmdb',
  'user' => 'ppawel',
  'password' => 'aa'
}

@conn = PGconn.open(:host => $config['host'], :port => $config['port'], :dbname => $config['dbname'], :user => $config['user'], :password => $config['password'])

tiler = Tiler.new(@conn)

@conn.query("SELECT id FROM changesets ORDER BY created_at DESC LIMIT #{LIMIT}").each do |row|
  @conn.transaction do |c|
    changeset_id = row['id'].to_i
    puts "Generating tiles for changeset #{changeset_id} at zoom level #{ZOOM_LEVEL}..."
    tile_count = tiler.generate(ZOOM_LEVEL, changeset_id)
    puts "Done, tile count: #{tile_count}"
  end
end
