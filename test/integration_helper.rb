# frozen_string_literal: true

require "stringio"
require "minitest/autorun"

ENV["RAILS_ENV"] = "test"

require "rails"
require "action_controller/railtie"
require "action_dispatch/testing/integration"
require "who_rendered"

APP_ROOT = File.expand_path("app_root", __dir__)
LOG_IO = StringIO.new

$LOAD_PATH.unshift APP_ROOT
$LOAD_PATH.unshift File.expand_path("outside_app", __dir__)

class TestApp < Rails::Application
  config.root = APP_ROOT
  config.eager_load = false
  config.consider_all_requests_local = true
  config.secret_key_base = "who_rendered" * 8
  config.hosts.clear
  config.logger = ActiveSupport::Logger.new(LOG_IO)
  config.log_level = :info
  config.active_support.report_deprecations = false
  # The app never calls load_defaults, so this would otherwise sit at 6.1, which
  # Rails 7.1 warns about on boot. 7.1 is accepted on every supported version.
  config.active_support.cache_format_version = 7.1
  config.paths["app/views"] = ["views"]
end

TestApp.initialize!

require "controllers/probe_controller"
require "controllers/wrapper_controller"
require "controllers/implicit_controller"
require "controllers/api_probe_controller"
require "controllers/selfish_controller"

Rails.application.routes.draw do
  get "/gated" => "probe#gated"
  get "/bounced" => "probe#bounced"
  get "/from_gem" => "probe#from_gem"
  get "/inline" => "probe#inline"
  get "/wrapped" => "wrapper#index"
  get "/implicit" => "implicit#show"
  get "/api" => "api_probe#index"
  get "/selfish" => "selfish#index"
end

# Normally set by rails/test_help, which we avoid because it requires ActiveRecord.
ActionDispatch::IntegrationTest.app = Rails.application

class IntegrationCase < ActionDispatch::IntegrationTest
  def setup
    WhoRendered.reset!
    clear_render_source
    WhoRendered.config.enabled = true
    reset_log
  end

  def teardown
    WhoRendered.reset!
    clear_render_source
  end

  # WhoRendered.reset! does not touch this, so without it a test that leaves a
  # value behind can hand it to whichever test minitest runs next.
  def clear_render_source
    Thread.current[WhoRendered::Payload::KEY] = nil
  end

  def reset_log
    LOG_IO.truncate(0)
    LOG_IO.rewind
  end

  # All three have to move. Rails.logger and ActionController::Base.logger for a
  # different reason on either side of Rails 8.2: through 8.1
  # ActionController::LogSubscriber#logger returns ActionController::Base.logger,
  # while on main it is an EventReporter::LogSubscriber that follows Rails.logger.
  #
  # And ActiveSupport::LogSubscriber.logger, which every log subscriber reads —
  # including the gem's. Through 8.1 it is `@logger ||= Rails.logger`, so it latches
  # whatever Rails.logger was at first read; leaving that behind pins every later
  # test's continuation lines to whatever logger this block installed. On main it is
  # an attr_reader assigned once at boot, so nothing can latch — which is why
  # omitting this swap fails on four legs out of five rather than all of them.
  # Swapping it is correct everywhere, and through 8.1 reading the original here
  # forces the memoization to happen against the right logger.
  def with_logger(logger)
    original = Rails.logger
    original_subscriber_logger = ActiveSupport::LogSubscriber.logger
    Rails.logger = logger
    ActionController::Base.logger = logger
    ActiveSupport::LogSubscriber.logger = logger
    yield
  ensure
    Rails.logger = original
    ActionController::Base.logger = original
    ActiveSupport::LogSubscriber.logger = original_subscriber_logger
  end

  def log
    LOG_IO.string
  end

  # Returns the process_action payload for the request made in the block.
  def payload_for
    captured = nil
    subscriber = ActiveSupport::Notifications.subscribe("process_action.action_controller") do |*args|
      captured = args.last
    end
    yield
    captured
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  # Ruby's frame label format changed in 3.4, so assertions ignore it.
  def strip_label(source)
    source.sub(/:in '.*'\z/, "")
  end
end
