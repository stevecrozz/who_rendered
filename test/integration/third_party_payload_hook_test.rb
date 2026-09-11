# frozen_string_literal: true

require "integration_helper"

# Nothing else in the suite covers a second party in append_info_to_payload.
#
# lograge's custom_payload support captures
# `ActionController::Base.instance_method(:append_info_to_payload)` and then
# define_methods a replacement onto ActionController::Base that calls the captured
# one. Prepended to Base, the gem's Payload was above Base in dispatch, so its super
# resolved to lograge's replacement, which called back into Payload: unbounded mutual
# recursion, SystemStackError on every request. WhoRendered.safely cannot catch that —
# SystemStackError is not a StandardError — so the gem did not even self-disable, it
# just took the application down.
#
# The invariant that fixes it is "ActionController::Base is above Payload in the
# ancestors", which prepending Payload to ActionController::Instrumentation gives us.
# lograge's define_method always lands on Base itself, so Base wins dispatch and
# Payload's super can only ever travel downward, into Instrumentation.
#
# Deliberately NOT asserted here: who owns the method lograge captures. Without
# ActiveRecord loaded that is Payload; in a real application it is
# ActiveRecord::Railties::ControllerRuntime, with Payload below it. Both are fine, and
# for the same reason, so pinning either would encode a property of this dummy app
# rather than the invariant.
class ThirdPartyPayloadHookTest < IntegrationCase
  def teardown
    uninstall_third_party_hook
    super
  end

  # The invariant itself, asserted directly: cheap, and it names the mistake.
  def test_payload_sits_below_action_controller_base_in_the_ancestors
    ancestors = ActionController::Base.ancestors

    assert_includes ancestors, WhoRendered::Payload
    assert_operator ancestors.index(WhoRendered::Payload), :>,
      ancestors.index(ActionController::Base),
      "Payload must not be prepended above ActionController::Base, or a third party " \
      "that redefines append_info_to_payload on Base becomes its own super"
  end

  # The same for API controllers, which get Payload through the same single prepend.
  def test_payload_sits_below_action_controller_api_in_the_ancestors
    ancestors = ActionController::API.ancestors

    assert_includes ancestors, WhoRendered::Payload
    assert_operator ancestors.index(WhoRendered::Payload), :>,
      ancestors.index(ActionController::API)
  end

  def test_a_third_party_that_rebinds_the_hook_does_not_recurse
    install_third_party_hook

    raising_exceptions { get "/gated" }

    assert_equal 403, response.status
    assert_match(/Rendered by: /, completed_line)
  end

  # The fix must not work by stranding the other party: their key has to survive too,
  # which rules out replacing the super call with a captured UnboundMethod of our own.
  def test_the_third_party_contribution_survives
    install_third_party_hook

    payload = payload_for { raising_exceptions { get "/gated" } }

    assert_equal({ probe: true }, payload[:custom_payload])
    assert_match(%r{controllers/probe_controller\.rb:#{ProbeController::FORBID_LINE}\b},
      payload[:render_source])
  end

  # API controllers reach Payload through Instrumentation rather than a prepend of their
  # own, so they need their own pass: this is the case a single prepend has to cover.
  def test_api_controllers_survive_the_same_treatment
    install_third_party_hook(ActionController::API)

    raising_exceptions { get "/api" }

    assert_equal 403, response.status
    assert_match(/Rendered by: /, completed_line)
  end

  private
    def install_third_party_hook(klass = ActionController::Base)
      # Verbatim lograge 0.11.2 Lograge.extend_base_class, minus the config lookup.
      captured = klass.instance_method(:append_info_to_payload)

      klass.send(:define_method, :append_info_to_payload) do |payload|
        captured.bind(self).call(payload)
        payload[:custom_payload] = { probe: true }
      end

      @third_party_hooked = klass
    end

    def uninstall_third_party_hook
      klass = @third_party_hooked
      return unless klass

      klass.send(:remove_method, :append_info_to_payload)
      @third_party_hooked = nil
    end

    # Without this, a regression takes minutes to surface instead of seconds: the
    # recursion raises SystemStackError, DebugExceptions catches it and renders the
    # exception page, and building that page from a stack that deep is what costs the
    # time. Letting the exception escape the request turns a four-minute timeout into an
    # immediate, legible error.
    def raising_exceptions
      key = "action_dispatch.show_exceptions"
      original = Rails.application.env_config[key]
      Rails.application.env_config[key] = :none
      yield
    ensure
      Rails.application.env_config[key] = original
    end

    def completed_line
      log.lines.grep(/^Completed /).last.to_s.strip
    end
end
