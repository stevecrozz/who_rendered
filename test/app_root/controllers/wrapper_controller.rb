# frozen_string_literal: true

class WrapperController < ActionController::Base
  before_action :require_admin

  DENY_LINE = __LINE__ + 2
  def deny
    head :forbidden
  end

  RENDER_403_LINE = __LINE__ + 2
  def render_403
    deny
  end

  REQUIRE_ADMIN_LINE = __LINE__ + 2
  def require_admin
    render_403
  end

  def index
    render plain: "unreachable"
  end
end
