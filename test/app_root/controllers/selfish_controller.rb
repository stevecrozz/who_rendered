# frozen_string_literal: true

# An application controller that overrides append_info_to_payload and forgets to
# call super. Because WhoRendered::Payload is prepended to ActionController::Base,
# this definition sits ahead of the gem's, so the gem's copy never runs for these
# requests: it can neither publish nor clear. Only the clear at
# start_processing.action_controller keeps the previous request's attribution off
# this request's Completed line.
class SelfishController < ActionController::Base
  def index
    render plain: "selfish"
  end

  private
    def append_info_to_payload(payload)
      payload[:selfish] = true
    end
end
