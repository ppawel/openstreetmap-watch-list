module ApiHelper
  def get_xyz(params)
    zoom = params[:zoom].to_i
    return params[:x].to_i * 2 ** (16 - zoom), params[:y].to_i * 2 ** (16 - zoom), zoom
  end

  def get_range(params)
    zoom = params[:zoom].to_i
    return zoom, params[:x1].to_i * 2 ** (16 - zoom), params[:y1].to_i * 2 ** (16 - zoom),
      params[:x2].to_i * 2 ** (16 - zoom), params[:y2].to_i * 2 ** (16 - zoom)
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
