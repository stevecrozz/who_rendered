# frozen_string_literal: true

require "active_support/log_subscriber"

module WhoRendered
  # Emits the frames that cannot fit on the Completed line. Only active when
  # config.frames > 1, since that is the only way more than one frame reaches
  # the payload.
  class LogSubscriber < ActiveSupport::LogSubscriber
    def process_action(event)
      WhoRendered.safely do
        frames = event.payload[:render_source_frames]
        next if frames.nil? || frames.size < 2

        target = WhoRendered.config.logger || logger
        next unless target

        frames.drop(1).each { |frame| target.info("  ↳ from #{frame}") }
      end
    end
  end
end
