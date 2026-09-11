# frozen_string_literal: true

require "integration_helper"

class PayloadTest < IntegrationCase
  def test_head_in_a_before_action
    payload = payload_for { get "/gated" }

    assert_equal 403, response.status
    assert_equal :head, payload[:render_method]
    assert_equal "controllers/probe_controller.rb:#{ProbeController::FORBID_LINE}",
      strip_label(payload[:render_source])
    assert_nil payload[:render_source_frames]
  end

  def test_redirect_to_in_a_before_action
    payload = payload_for { get "/bounced" }

    assert_equal 302, response.status
    assert_equal :redirect_to, payload[:render_method]
    assert_equal "controllers/probe_controller.rb:#{ProbeController::BOUNCE_LINE}",
      strip_label(payload[:render_source])
  end

  def test_render_inside_the_action_body
    payload = payload_for { get "/inline" }

    assert_equal 200, response.status
    assert_equal :render, payload[:render_method]
    assert_equal "controllers/probe_controller.rb:#{ProbeController::INLINE_LINE}",
      strip_label(payload[:render_source])
  end

  def test_render_from_outside_the_application
    payload = payload_for { get "/from_gem" }

    assert_equal 403, response.status
    assert_match(/fake_gem\.rb:#{FakeGem::BLOCK_LINE}\b/, payload[:render_source])
    refute_match(/\A#{Regexp.escape(APP_ROOT)}/, payload[:render_source])
  end

  def test_implicit_render_reports_nothing
    payload = payload_for { get "/implicit" }

    assert_equal 200, response.status
    assert_nil payload[:render_source]
    assert_nil payload[:render_method]
  end

  def test_api_controllers_are_hooked
    payload = payload_for { get "/api" }

    assert_equal 403, response.status
    assert_equal "controllers/api_probe_controller.rb:#{ApiProbeController::FORBID_LINE}",
      strip_label(payload[:render_source])
  end

  def test_reports_nothing_when_disabled
    WhoRendered.config.enabled = false

    payload = payload_for { get "/gated" }

    assert_equal 403, response.status
    assert_nil payload[:render_source]
  end

  def test_reports_the_innermost_application_frame
    payload = payload_for { get "/wrapped" }

    assert_equal 403, response.status
    assert_equal "controllers/wrapper_controller.rb:#{WrapperController::DENY_LINE}",
      strip_label(payload[:render_source])
  end
end
