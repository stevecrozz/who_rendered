# frozen_string_literal: true

module WhoRendered
  # Publishes the captured call site: to the process_action payload for anyone
  # subscribing to it, and to the Completed line through
  # ActionController::Base.log_process_action — the same hook ActiveRecord uses
  # to add "ActiveRecord: 1.2ms" to that line.
  module Payload
    # The Completed line's text travels out of band rather than through the
    # payload, because the payload log_process_action receives is not always the
    # one append_info_to_payload wrote to. On Rails main the Completed line is
    # built from the structured event, whose additions are a hardcoded
    # payload.slice, so a custom payload key is dropped before
    # log_process_action runs. A fiber-local is written and read in the same
    # fiber — the log subscriber is invoked synchronously inside process_action
    # on every supported version — and depends on no Rails internals.
    KEY = :__who_rendered_source # :nodoc:

    # Cleared at the start of every instrumented request, from
    # start_processing.action_controller.
    #
    # The read cannot be what clears it. Rails 7.1's BroadcastLogger#info hands
    # the same block to each of its sinks with no memoization, and Rails builds
    # the Completed line inside that block, so log_process_action runs once per
    # sink. A destructive read would put the attribution in the first sink only —
    # under `rails server` on 7.1 that means the log file has it and the terminal
    # does not.
    #
    # Nor can clearing on write be enough. Payload is prepended to
    # ActionController::Base, so a controller's own append_info_to_payload sits
    # ahead of ours; one that omits super stops ours from running at all, leaving
    # the previous request's value to be reported against this one.
    #
    # Clearing at the request boundary answers both, and needs neither a logger
    # nor cooperation from the application: start_processing is emitted from
    # ActionController::Instrumentation#process_action on every supported version,
    # immediately before the action runs and always in the same fiber that will
    # later read the value. ActionController::Live matters here — it copies the
    # parent thread's fiber-locals into the streaming thread, so the child starts
    # out holding a stale value, and this clear is what removes it.
    def self.clear_source
      Thread.current[KEY] = nil
    end

    module ClassMethods
      def log_process_action(payload)
        messages = super

        WhoRendered.safely do
          source = Thread.current[KEY]
          messages << "Rendered by: #{source}" if source
        end

        messages
      end
    end

    private
      # Private to match ActionController::Instrumentation.
      def append_info_to_payload(payload)
        super

        WhoRendered.safely do
          # Redundant with the boundary clear for any request that reaches here,
          # and kept anyway: unsubscribing "start_processing.action_controller" by
          # name — the usual recipe for silencing the "Processing by" line — drops
          # every listener for that event, ours included. Two independent guards,
          # because the cost of the last one failing is naming the wrong file.
          Thread.current[KEY] = nil

          data = __who_rendered_data
          next unless data

          source = data[:frames].first

          payload[:render_source] = source
          payload[:render_source_frames] = data[:frames] if data[:frames].size > 1
          payload[:render_method] = data[:method]

          Thread.current[KEY] = source
        end
      end
  end
end
