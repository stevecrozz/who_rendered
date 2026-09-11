# frozen_string_literal: true

require "integration_helper"

class CompletedLineTest < IntegrationCase
  def test_completed_line_names_the_render_source
    get "/gated"

    line = completed_line

    assert_match(/\ACompleted 403 Forbidden/, line)
    assert_match(%r{Rendered by: controllers/probe_controller\.rb:#{ProbeController::FORBID_LINE}\b},
      line)
  end

  def test_rendered_by_joins_the_existing_additions
    get "/inline"

    assert_match(/\(Views: [\d.]+ms \| Rendered by: /, completed_line)
  end

  def test_api_controllers_get_the_addition_too
    get "/api"

    assert_match(
      %r{Rendered by: controllers/api_probe_controller\.rb:#{ApiProbeController::FORBID_LINE}\b},
      completed_line
    )
  end

  def test_completed_line_is_untouched_for_implicit_render
    get "/implicit"

    assert_match(/\ACompleted 200 OK/, completed_line)
    refute_match(/Rendered by:/, completed_line)
  end

  def test_completed_line_is_untouched_when_disabled
    WhoRendered.config.enabled = false

    get "/gated"

    refute_match(/Rendered by:/, log)
  end

  def test_no_extra_log_lines_are_emitted_by_default
    # Capture log with gem disabled.
    WhoRendered.config.enabled = false
    get "/gated"
    disabled_log = log
    disabled_lines = disabled_log.lines

    # Capture log with gem enabled.
    reset_log
    WhoRendered.reset!
    WhoRendered.config.enabled = true
    get "/gated"
    enabled_log = log
    enabled_lines = enabled_log.lines

    # Assert same number of lines.
    assert_equal disabled_lines.size, enabled_lines.size,
      "Expected same number of log lines, got #{disabled_lines.size} vs #{enabled_lines.size}"

    # Assert only the Completed line differs.
    disabled_lines.zip(enabled_lines).each_with_index do |(disabled_line, enabled_line), index|
      if disabled_line =~ /^Completed /
        refute_equal disabled_line, enabled_line,
          "Expected Completed line to differ at index #{index}"
      else
        assert_equal disabled_line, enabled_line,
          "Expected non-Completed lines to match at index #{index}"
      end
    end

    # Confirm no arrow character appears (no continuation lines).
    refute_match(/↳/, enabled_log)
  end

  # The Completed line's text does not travel through the payload, because the
  # payload log_process_action receives is not always the one
  # append_info_to_payload wrote to. Rails main builds that line from the
  # structured event, whose additions are a hardcoded payload.slice.
  def test_the_addition_does_not_come_from_the_payload_argument
    Thread.current[WhoRendered::Payload::KEY] = "somewhere.rb:12:in 'somewhere'"

    messages = ActionController::Base.log_process_action({})

    assert_includes messages.join(" | "), "Rendered by: somewhere.rb:12:in 'somewhere'"
  end

  # The first guard, tested through the one case only it covers: SelfishController
  # overrides append_info_to_payload without super, so the gem's copy never runs
  # and cannot clear. Without the start_processing clear this reports /gated's call
  # site against a request that rendered from somewhere else entirely.
  def test_a_controller_that_bypasses_the_write_hook_inherits_nothing
    get "/gated"
    assert_match(/Rendered by:/, completed_line)

    reset_log
    get "/selfish"

    assert_match(/\ACompleted 200 OK/, completed_line)
    refute_match(/Rendered by:/, log)
  end

  # The second guard, tested on its own because the boundary clear would otherwise
  # mask it: calling the hook directly is the only way to reach it without
  # start_processing having already run.
  def test_the_write_hook_clears_stale_state_by_itself
    Thread.current[WhoRendered::Payload::KEY] = "stale.rb:1:in 'stale'"

    ProbeController.new.send(:append_info_to_payload, {})

    assert_nil Thread.current[WhoRendered::Payload::KEY]
  end

  # Rails 7.1's BroadcastLogger#info hands the same block to every sink without
  # memoizing it, and Rails builds the Completed line inside that block, so
  # log_process_action runs once per sink. Reading must not be destructive, or
  # only the first sink gets the attribution.
  def test_every_sink_of_a_broadcast_logger_gets_the_addition
    sinks = [StringIO.new, StringIO.new]
    broadcast = ActiveSupport::BroadcastLogger.new(
      *sinks.map { |io| ActiveSupport::Logger.new(io) }
    )

    with_logger(broadcast) { get "/gated" }

    sinks.each_with_index do |io, index|
      line = io.string.lines.grep(/^Completed /).last.to_s
      assert_match(/Rendered by: /, line, "Expected sink #{index} to carry the addition")
    end
  end

  # A request whose Completed line is never logged leaves its value unread, so
  # the clear cannot happen on read alone.
  def test_a_value_written_but_never_logged_does_not_reach_the_next_request
    begin
      Rails.logger.level = :warn
      get "/gated"
    ensure
      Rails.logger.level = :info
    end
    reset_log

    get "/implicit"

    refute_match(/Rendered by:/, log)
  end

  def test_a_request_that_reports_nothing_does_not_inherit_the_previous_one
    get "/gated"
    assert_match(/Rendered by:/, completed_line)

    reset_log
    get "/implicit"

    assert_match(/\ACompleted 200 OK/, completed_line)
    refute_match(/Rendered by:/, log)
  end

  private
    def completed_line
      log.lines.grep(/^Completed /).last.to_s.strip
    end
end
