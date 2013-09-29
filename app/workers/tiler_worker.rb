class TilerWorker
  include Sidekiq::Worker
  #include SidekiqStatus::Worker

  sidekiq_options :retry => false

  def initialize
    @conn = ActiveRecord::Base.connection.raw_connection()
    @conn.set_error_verbosity(0)
    @tiler = Tiler::ChangesetTiler.new(@conn)
  end

  def perform(changeset_id)
    zoom = 16
    before = Time.now
    puts "Generating tiles for changeset #{changeset_id}..."
    tile_count = @tiler.generate(zoom, changeset_id, {})
    puts "Done, tile count: #{tile_count}"
    puts "Changeset #{changeset_id} took #{Time.now - before}s"
    { tiles: tile_count }
  end

  def self.job_name(changeset_id)
    changeset_id
  end
end
