module ApiHelper
  def get_xyz(params)
    return params[:x].to_i, params[:y].to_i, params[:zoom].to_i
  end

  def get_limit(params)
    return (params[:limit] || 20).to_i
  end
end
