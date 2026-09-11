# frozen_string_literal: true

module WhoRendered
  # Captures the call site of a response-producing method. Capture only: this
  # module never logs, formats, or decides what to print.
  #
  # Each wrapper calls super first and inspects state afterwards, so the gem
  # never has to parse Rails' render arguments — the part of that API most
  # likely to change between versions. Bare `super` forwards the original
  # arguments verbatim, keywords included.
  module ControllerHooks
    def render(*args, **kwargs, &block)
      result = super
      __who_rendered_note(:render, caller_locations(1)) if __who_rendered_capture?
      result
    end

    def head(*args, **kwargs, &block)
      result = super
      __who_rendered_note(:head, caller_locations(1)) if __who_rendered_capture?
      result
    end

    def redirect_to(*args, **kwargs, &block)
      result = super
      __who_rendered_note(:redirect_to, caller_locations(1)) if __who_rendered_capture?
      result
    end

    def __who_rendered_data # :nodoc:
      defined?(@__who_rendered) ? @__who_rendered : nil
    end

    private
      # Cheap pre-check, so the stack is only walked when the result will be
      # used. Returns nil on an internal error, which reads as false.
      def __who_rendered_capture?
        WhoRendered.safely do
          next false unless WhoRendered.active?
          next false if __who_rendered_data
          next true if WhoRendered.config.capture == :always

          status = response&.status
          !status || !(200..299).cover?(status)
        end
      end

      def __who_rendered_note(method_name, locations)
        WhoRendered.safely do
          next if locations.nil? || locations.empty?
          next if WhoRendered.call_site.implicit_render?(locations.first)

          frames = WhoRendered.call_site.frames(locations, limit: WhoRendered.config.frames)
          next if frames.empty?

          @__who_rendered = { method: method_name, frames: frames.map(&:to_s) }
        end
      end
  end
end
