# frozen_string_literal: true

require "integration_helper"

class ContinuationLinesTest < IntegrationCase
  def test_three_frames_produce_two_continuation_lines
    WhoRendered.config.frames = 3

    get "/wrapped"

    assert_match(%r{Rendered by: controllers/wrapper_controller\.rb:#{WrapperController::DENY_LINE}\b},
      log)
    assert_match(
      %r{^  ↳ from controllers/wrapper_controller\.rb:#{WrapperController::RENDER_403_LINE}\b},
      log
    )
    assert_match(
      %r{^  ↳ from controllers/wrapper_controller\.rb:#{WrapperController::REQUIRE_ADMIN_LINE}\b},
      log
    )
    assert_equal 2, log.lines.count { |line| line.include?("↳ from ") }
  end

  def test_continuation_lines_follow_the_completed_line
    WhoRendered.config.frames = 3

    get "/wrapped"

    lines = log.lines
    completed_index = lines.index { |line| line.start_with?("Completed ") }
    first_arrow_index = lines.index { |line| line.include?("↳ from ") }

    refute_nil completed_index
    refute_nil first_arrow_index
    assert_operator first_arrow_index, :>, completed_index
  end

  def test_single_frame_produces_no_continuation_lines
    WhoRendered.config.frames = 1

    get "/wrapped"

    refute_match(/↳ from /, log)
  end

  def test_payload_carries_every_frame_when_frames_is_greater_than_one
    WhoRendered.config.frames = 3

    payload = payload_for { get "/wrapped" }

    assert_equal 3, payload[:render_source_frames].size
    assert_equal payload[:render_source], payload[:render_source_frames].first
  end
end
