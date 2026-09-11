# frozen_string_literal: true

class ImplicitController < ActionController::Base
  # No render call anywhere: Rails renders the template for us, from
  # BasicImplicitRender#send_action, after this method has already returned.
  def show
  end
end
