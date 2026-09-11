# frozen_string_literal: true

require "unit_helper"

class WhoRenderedTest < Minitest::Test
  class FakeLogger
    attr_reader :warnings, :infos

    def initialize
      @warnings = []
      @infos = []
    end

    def warn(message = nil)
      @warnings << (message || yield)
    end

    def info(message = nil)
      @infos << (message || yield)
    end
  end

  def setup
    WhoRendered.reset!
    @logger = FakeLogger.new
    WhoRendered.configure do |config|
      config.enabled = true
      config.logger = @logger
    end
  end

  def teardown
    WhoRendered.reset!
  end

  def test_active_when_enabled_and_not_disabled
    assert_predicate WhoRendered, :active?
  end

  def test_not_active_when_configuration_disables_it
    WhoRendered.config.enabled = false

    refute_predicate WhoRendered, :active?
  end

  def test_safely_returns_the_block_value
    assert_equal 42, WhoRendered.safely { 42 }
  end

  def test_safely_swallows_errors_and_disables_the_gem
    result = WhoRendered.safely { raise "boom" }

    assert_nil result
    assert_predicate WhoRendered, :disabled?
    refute_predicate WhoRendered, :active?
  end

  def test_safely_does_not_swallow_exceptions_outside_standard_error
    assert_raises(NotImplementedError) { WhoRendered.safely { raise NotImplementedError } }
  end

  def test_disable_warns_exactly_once
    WhoRendered.safely { raise "first" }
    WhoRendered.safely { raise "second" }

    assert_equal 1, @logger.warnings.size
    assert_match(/who_rendered disabled/, @logger.warnings.first)
    assert_match(/first/, @logger.warnings.first)
  end

  def test_reset_clears_the_disabled_flag
    WhoRendered.safely { raise "boom" }
    WhoRendered.reset!

    refute_predicate WhoRendered, :disabled?
  end

  def test_call_site_is_memoized
    assert_same WhoRendered.call_site, WhoRendered.call_site
  end

  def test_call_site_ignores_this_gems_own_frames
    location = Struct.new(:absolute_path, :lineno, :label) do
      def path
        absolute_path
      end
    end.new(File.expand_path("../../lib/who_rendered/controller_hooks.rb", __dir__), 10, "render")

    assert_empty WhoRendered.call_site.frames([location], limit: 1)
  end

  def test_safely_with_logger_that_raises_still_disables_gem
    broken_logger = Class.new do
      def warn(_message)
        raise "logger broken"
      end

      def info(_message)
        # no-op
      end
    end.new

    WhoRendered.config.logger = broken_logger

    result = WhoRendered.safely { raise "first fault" }

    assert_nil result
    assert_predicate WhoRendered, :disabled?
  end
end
