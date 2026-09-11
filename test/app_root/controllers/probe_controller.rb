# frozen_string_literal: true

require "fake_gem"

class ProbeController < ActionController::Base
  include FakeGem

  before_action :forbid, only: :gated
  before_action :bounce, only: :bounced
  before_action :fake_gem_block, only: :from_gem

  FORBID_LINE = __LINE__ + 2
  def forbid
    head :forbidden
  end

  BOUNCE_LINE = __LINE__ + 2
  def bounce
    redirect_to "/elsewhere"
  end

  INLINE_LINE = __LINE__ + 2
  def inline
    render plain: "ok"
  end

  def gated
    render plain: "unreachable"
  end

  def bounced
    render plain: "unreachable"
  end

  def from_gem
    render plain: "unreachable"
  end
end
