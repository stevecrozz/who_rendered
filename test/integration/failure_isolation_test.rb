# frozen_string_literal: true

require "integration_helper"

class FailureIsolationTest < IntegrationCase
  # Duck-types CallSite and fails on the first call the hooks make.
  class ExplodingCallSite
    def implicit_render?(_location)
      raise "internal bug"
    end

    def frames(_locations, limit: 1)
      raise "internal bug"
    end
  end

  def with_exploding_call_site
    WhoRendered.instance_variable_set(:@call_site, ExplodingCallSite.new)
    yield
  ensure
    WhoRendered.instance_variable_set(:@call_site, nil)
  end

  def test_an_internal_error_does_not_break_the_request
    with_exploding_call_site { get "/gated" }

    assert_equal 403, response.status
    assert_match(/^Completed 403 Forbidden/, log)
  end

  def test_an_internal_error_disables_the_gem
    with_exploding_call_site { get "/gated" }

    assert_predicate WhoRendered, :disabled?
    refute_predicate WhoRendered, :active?
  end

  def test_an_internal_error_warns_once_and_adds_no_source
    with_exploding_call_site do
      get "/gated"
      get "/inline"
    end

    assert_equal 1, log.lines.count { |line| line.include?("who_rendered disabled") }
    refute_match(/Rendered by:/, log)
  end

  def test_requests_keep_working_after_the_gem_disables_itself
    with_exploding_call_site { get "/gated" }
    reset_log

    get "/inline"

    assert_equal 200, response.status
    assert_equal "ok", response.body
  end
end
