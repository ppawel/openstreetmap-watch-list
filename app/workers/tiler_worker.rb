class TilerWorker
  include SidekiqStatus::Worker

  sidekiq_options :retry => false

  def perform(name, count)
    zoom = 16
    changeset_ids = []

    conn = ActiveRecord::Base.connection.raw_connection()
    #conn.set_error_verbosity(0)
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
  end
end
