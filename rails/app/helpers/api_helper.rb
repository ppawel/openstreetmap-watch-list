module ApiHelper
  def get_xyz(params)
    return params[:x].to_i, params[:y].to_i, params[:zoom].to_i
  end

  def get_range(params)
    return params[:zoom].to_i, params[:x1].to_i, params[:y1].to_i, params[:x2].to_i, params[:y2].to_i
  end

  def get_limit_sql(params)
    limit = (params[:limit] || 30).to_i
    limit = 30 if limit <= 0
    sql = " LIMIT #{limit}"
    sql += " OFFSET #{params[:offset].to_i}" if params[:offset]
    return sql
  end

  def get_timelimit_sql(params)
    return (params[:timelimit] and params[:timelimit].to_i > 0) ? " AND tstamp >= (NOW() - interval '#{params[:timelimit].to_i} hour')" : ''
  end
end
