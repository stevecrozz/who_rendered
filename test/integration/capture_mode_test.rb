# frozen_string_literal: true

require "integration_helper"

class CaptureModeTest < IntegrationCase
  def test_non_2xx_mode_still_reports_error_responses
    WhoRendered.config.capture = :non_2xx

    payload = payload_for { get "/gated" }

    assert_equal 403, response.status
    assert_match(/probe_controller\.rb:#{ProbeController::FORBID_LINE}\b/, payload[:render_source])
  end

  def test_non_2xx_mode_still_reports_redirects
    WhoRendered.config.capture = :non_2xx

    payload = payload_for { get "/bounced" }

    assert_equal 302, response.status
    assert_match(/probe_controller\.rb:#{ProbeController::BOUNCE_LINE}\b/, payload[:render_source])
  end

  def test_non_2xx_mode_skips_successful_responses
    WhoRendered.config.capture = :non_2xx

    payload = payload_for { get "/inline" }

    assert_equal 200, response.status
    assert_nil payload[:render_source]
  end

  def test_always_mode_reports_successful_responses
    WhoRendered.config.capture = :always

    payload = payload_for { get "/inline" }

    assert_equal 200, response.status
    assert_match(/probe_controller\.rb:#{ProbeController::INLINE_LINE}\b/, payload[:render_source])
  end
end
