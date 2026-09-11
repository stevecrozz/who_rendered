# frozen_string_literal: true

module WhoRendered
  # User-facing settings. See README for the meaning of each.
  class Configuration
    CAPTURE_MODES = [:always, :non_2xx].freeze

    # nil means "decide from the Rails environment when asked".
    attr_accessor :enabled
    attr_reader :logger, :frames, :capture

    def initialize
      @enabled = nil
      @frames = 1
      @capture = :always
      @logger = nil
    end

    def enabled?
      return !!@enabled unless @enabled.nil?

      !!(defined?(::Rails.env) && ::Rails.env.local?)
    end

    def logger=(value)
      unless value.nil? || (value.respond_to?(:warn) && value.respond_to?(:info))
        raise ArgumentError, "logger must be nil or respond to :warn and :info, got #{value.inspect}"
      end

      @logger = value
    end

    def frames=(value)
      unless value.is_a?(Integer)
        raise ArgumentError, "frames must be an Integer, got #{value.inspect}"
      end

      raise ArgumentError, "frames must be >= 1, got #{value}" if value < 1

      @frames = value
    end

    def capture=(value)
      unless CAPTURE_MODES.include?(value)
        raise ArgumentError, "capture must be :always or :non_2xx, got #{value.inspect}"
      end

      @capture = value
    end
  end
end
