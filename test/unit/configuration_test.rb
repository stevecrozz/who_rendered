# frozen_string_literal: true

require "unit_helper"

class ConfigurationTest < Minitest::Test
  def setup
    WhoRendered.reset!
  end

  def teardown
    WhoRendered.reset!
  end

  def test_defaults
    config = WhoRendered::Configuration.new

    assert_nil config.enabled
    assert_equal 1, config.frames
    assert_equal :always, config.capture
    assert_nil config.logger
  end

  def test_enabled_predicate_is_false_outside_rails
    config = WhoRendered::Configuration.new

    assert_equal false, config.enabled?
  end

  def test_enabled_predicate_honours_explicit_setting
    config = WhoRendered::Configuration.new

    config.enabled = true
    assert_equal true, config.enabled?

    config.enabled = false
    assert_equal false, config.enabled?
  end

  def test_frames_must_be_at_least_one
    config = WhoRendered::Configuration.new

    config.frames = 3
    assert_equal 3, config.frames

    error = assert_raises(ArgumentError) { config.frames = 0 }
    assert_match(/frames must be >= 1/, error.message)
  end

  def test_frames_must_be_an_integer
    config = WhoRendered::Configuration.new

    error = assert_raises(ArgumentError) { config.frames = nil }
    assert_match(/frames must be an Integer/, error.message)

    error = assert_raises(ArgumentError) { config.frames = 2.9 }
    assert_match(/frames must be an Integer/, error.message)
  end

  def test_logger_must_respond_to_warn_and_info
    config = WhoRendered::Configuration.new

    valid_logger = Struct.new(:warn, :info).new(proc {}, proc {})
    def valid_logger.warn(_msg); end
    def valid_logger.info(_msg); end
    config.logger = valid_logger
    assert_equal valid_logger, config.logger

    config.logger = nil
    assert_nil config.logger

    error = assert_raises(ArgumentError) { config.logger = $stdout }
    assert_match(/logger must be nil or respond to :warn and :info/, error.message)
  end

  def test_capture_rejects_unknown_modes
    config = WhoRendered::Configuration.new

    config.capture = :non_2xx
    assert_equal :non_2xx, config.capture

    error = assert_raises(ArgumentError) { config.capture = :sometimes }
    assert_match(/capture must be :always or :non_2xx/, error.message)
  end

  def test_configure_yields_the_singleton_config
    WhoRendered.configure { |config| config.frames = 4 }

    assert_equal 4, WhoRendered.config.frames
  end

  def test_reset_restores_defaults
    WhoRendered.configure { |config| config.frames = 4 }
    WhoRendered.reset!

    assert_equal 1, WhoRendered.config.frames
  end

  def test_version_is_a_string
    assert_kind_of String, WhoRendered::VERSION
  end
end
