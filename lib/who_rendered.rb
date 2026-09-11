# frozen_string_literal: true

require "who_rendered/version"
require "who_rendered/configuration"
require "who_rendered/call_site"

module WhoRendered
  # Rails components whose frames are never the answer to "who rendered?".
  FRAMEWORK_GEMS = ["actionpack", "actionview", "activesupport", "railties"].freeze

  class << self
    def config
      @config ||= Configuration.new
    end

    def configure
      yield config
      config
    end

    def reset!
      @config = nil
      @disabled = false
      @call_site = nil
    end

    def active?
      !disabled? && config.enabled?
    end

    def disabled?
      !!@disabled
    end

    # Runs the gem's own work. An internal bug must never reach the application,
    # so any StandardError takes the gem out of service for the rest of the
    # process instead of raising into a request.
    def safely
      yield
    rescue StandardError => error
      # The inner rescue ensures the gem is disabled even if warning fails.
      begin
        disable!(error)
      rescue StandardError
        @disabled = true
      end
      nil
    end

    # Warning once is best-effort under concurrency: two threads faulting at the
    # same instant can both pass the guard and both warn. Harmless under MRI, and
    # not worth a mutex in the render path.
    def disable!(error)
      return if disabled?

      @disabled = true
      warn_about(error)
    end

    def call_site
      @call_site ||= CallSite.new(
        app_root: app_root,
        framework_roots: framework_roots,
        own_root: __dir__
      )
    end

    private
      def app_root
        defined?(::Rails.root) && ::Rails.root ? ::Rails.root.to_s : nil
      end

      # Resolved through loaded specs rather than a path pattern, so this is
      # still correct when Rails is a path: or git: dependency.
      def framework_roots
        FRAMEWORK_GEMS.filter_map { |name| Gem.loaded_specs[name]&.full_gem_path }
      end

      def warn_about(error)
        message = "who_rendered disabled for this process after an internal error: " \
                  "#{error.class}: #{error.message}"
        logger = config.logger
        logger ||= ::Rails.logger if defined?(::Rails.logger)

        logger ? logger.warn(message) : Kernel.warn(message)
      end
  end
end

require "who_rendered/railtie" if defined?(::Rails::Railtie)
