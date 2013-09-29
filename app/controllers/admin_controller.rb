class AdminController < ActionController::Base
  protect_from_forgery

  def spawn_workers
    #post_params[]
    #TilerWorker.perform_async(params[:changeset_id])
    sql = 'SELECT DISTINCT changeset_id AS id FROM nodes LIMIT 100'

    for row in ActiveRecord::Base.connection.execute(sql) do
      TilerWorker.perform_async(row['id'].to_i)
    end

    redirect_to '/admin'
  end
end
