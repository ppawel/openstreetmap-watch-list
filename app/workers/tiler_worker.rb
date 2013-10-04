class TilerWorker
  @queue = :tiler

  def self.perform(changeset_id)
    @conn = ActiveRecord::Base.connection.raw_connection()
    @conn.set_error_verbosity(0)
    @tiler = Tiler::ChangesetTiler.new(@conn)
    zoom = 18
    before = Time.now
    puts "Generating tiles for changeset #{changeset_id}..."
    tile_count = @tiler.generate(zoom, changeset_id, {})
    puts "Done, tile count: #{tile_count}"
    puts "Changeset #{changeset_id} took #{Time.now - before}s"
    { tiles: tile_count }
  end
end
