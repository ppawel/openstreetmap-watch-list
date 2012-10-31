require 'pg'

if ARGV.size != 2
  puts "Usage: generate_tiles.rb <zoom level> <limit> [offset]"
  exit
end

ZOOM_LEVEL = ARGV[0]
LIMIT = ARGV[1]
OFFSET = ARGV[2] || 100

$config = {
  'host' => 'localhost',
  'port' => 5432,
  'dbname' => 'osmdb',
  'user' => 'ppawel',
  'password' => 'aa'
}

@conn = PGconn.open(:host => $config['host'], :port => $config['port'], :dbname => $config['dbname'], :user => $config['user'], :password => $config['password'])

@conn.query("SELECT id FROM changesets ORDER BY created_at DESC LIMIT #{LIMIT}").each do |row|
  changeset_id = row['id'].to_i
  puts "Generating tiles for changeset #{changeset_id} at zoom level #{ZOOM_LEVEL}..."
  tile_count = @conn.query("SELECT OWL_GenerateChangesetTiles(#{changeset_id}, #{ZOOM_LEVEL})").getvalue(0, 0)
  puts "Done, tile count: #{tile_count}"
end
