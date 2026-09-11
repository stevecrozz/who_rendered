# frozen_string_literal: true

require "integration_helper"

class DefaultEnabledTest < IntegrationCase
  def test_enabled_defaults_to_rails_env_local
    WhoRendered.reset!
    # Do not set enabled explicitly; let it use its default.

    assert_equal Rails.env.local?, WhoRendered.config.enabled?
  end
end
