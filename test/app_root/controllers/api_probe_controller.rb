# frozen_string_literal: true

class ApiProbeController < ActionController::API
  before_action :forbid

  FORBID_LINE = __LINE__ + 2
  def forbid
    head :forbidden
  end

  def index
    render plain: "unreachable"
  end
end
