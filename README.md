# who_rendered

<p align="center">
  <img src="doc/who-rendered.png" width="360"
       alt="Retro poster in 1950s advertising style: a startled woman glances sideways with a hand over her mouth, above the words &ldquo;Who Rendered?&rdquo;">
</p>

Find out who called render. Adds the file and line that produced a Rails response to the
`Completed` log line — so an unexplained 403 names its own source.

## Before

```
Processing by Admin::ReportsController#index as HTML
Filter chain halted as :require_admin rendered or redirected
Completed 403 Forbidden in 3ms (Views: 0.0ms | ActiveRecord: 0.5ms)
```

## After

```
Processing by Admin::ReportsController#index as HTML
Filter chain halted as :require_admin rendered or redirected
Completed 403 Forbidden in 3ms (Views: 0.0ms | ActiveRecord: 0.5ms | Rendered by: app/controllers/concerns/admin_gate.rb:14:in 'require_admin')
```

## Install

```ruby
# Gemfile
gem "who_rendered", group: :development
```

No configuration is required. By default the gem is active in development and test, and adds
no log lines of its own — only the `Rendered by:` text on the `Completed` line Rails already
prints.

## Configuration

```ruby
# config/initializers/who_rendered.rb
WhoRendered.configure do |config|
  config.enabled = Rails.env.local?  # default
  config.frames  = 1                 # default
  config.capture = :always           # default
  config.logger  = nil               # default: Rails.logger
end
```

| Setting   | Default            | Meaning                                                                                |
| --------- | ------------------ | -------------------------------------------------------------------------------------- |
| `enabled` | `Rails.env.local?` | When false, every hook becomes a pass-through.                                          |
| `frames`  | `1`                | Frames to report. `1` is the `Completed` line only; more adds `↳ from` lines after it.   |
| `capture` | `:always`          | `:non_2xx` skips the stack walk on successful responses.                                |
| `logger`  | `nil`              | Used for the `↳ from` lines only.                                                       |

## When the render comes from a dependency

If the response was produced entirely inside a gem — a `before_action` from an included
module, a gem's `rescue_from` handler — there is no application frame to report. The gem
names the dependency instead of going quiet:

```
Completed 401 Unauthorized in 2ms (Rendered by: devise-4.9.4/lib/devise/controllers/helpers.rb:99:in 'authenticate_user!')
```

## Wrapper helpers and `frames`

If your renders go through a helper, the innermost application frame is that helper — the
same line for every 403 in the app. Set `frames` above 1 so the helper cannot hide its
caller:

```ruby
WhoRendered.configure { |config| config.frames = 3 }
```

```
Completed 403 Forbidden in 3ms (Views: 0.0ms | Rendered by: app/controllers/application_controller.rb:88:in 'render_403')
  ↳ from app/controllers/concerns/admin_gate.rb:14:in 'require_admin'
  ↳ from app/controllers/admin/reports_controller.rb:3:in 'index'
```

## What it does not report

Requests where the application never called `render` — the `def show; end` case, where Rails
renders the template for you. There is no decision to attribute, and `Processing by
PostsController#show` already tells you where to look.

## How it works

A prepended module wraps `render`, `head`, and `redirect_to`, calls `super`, and records the
call stack. At the end of the action, the documented hook `append_info_to_payload` adds the
frames to the `process_action.action_controller` payload, and an override of
`ActionController::Base.log_process_action` appends the `Rendered by:` text to the `Completed`
line — the same pair of hooks Active Record uses to add `ActiveRecord: 1.2ms` to that line.

The `Completed` line's text is handed between those two hooks out of band rather than through
the payload, since the payload `log_process_action` receives is not always the one
`append_info_to_payload` wrote to. That is what keeps the feature working on every supported
version without a version check.

The gem also subscribes to `start_processing.action_controller` to empty that hand-off slot at
the top of every instrumented request, which is what stops one request's attribution from
reaching the next. Unsubscribing that event *by name* — the usual recipe for silencing the
`Processing by` line — removes every listener for it, including this one. The write hook clears
the slot too, so almost nothing changes if that happens; misattribution needs both the missing
subscription *and* a controller whose own `append_info_to_payload` does not call `super`.

Payload keys, for anyone subscribing to `process_action.action_controller` directly:

| Key                     | Type                                             |
| ----------------------- | ------------------------------------------------ |
| `:render_source`        | `String`                                         |
| `:render_source_frames` | `Array<String>` (only when `frames > 1`)         |
| `:render_method`        | `Symbol` — `:render`, `:head`, or `:redirect_to` |

If the gem hits an internal error it logs one warning and disables itself for the rest of the
process. It never raises into a request.

## Limitations

- **Structured events do not carry the data on Rails 8.1+.**
  `ActionController::StructuredEventSubscriber#additions_for` is a hardcoded
  `payload.slice(:view_runtime, :db_runtime, :queries_count, :cached_queries_count)`, so
  custom keys are dropped from the `action_controller.request_completed` structured event.
  `ActiveSupport::Notifications` subscribers are unaffected; they receive every key. The text
  log is unaffected too, because the `Rendered by:` text does not travel through a payload at
  all. Making the slice extensible is a small upstream change worth proposing separately.
- **lograge replaces the `Completed` line, so you have to bridge the payload yourself.**
  lograge calls `remove_existing_log_subscriptions`, which unsubscribes
  `ActionController::LogSubscriber` — a lograge app has no `Completed` line at all, and the
  `Rendered by:` text has nowhere to go. `payload[:render_source]` is still there, so pass it
  through:

  ```ruby
  config.lograge.custom_options = lambda do |event|
    { rendered_by: event.payload[:render_source] }.compact
  end
  ```

- **Overlaps with `verbose_redirect_logs` on Rails 8.1+.** Both may report a redirect's
  origin. The gem does not suppress the Rails feature; the two disagree usefully, since Rails
  prints nothing when the redirect comes from a gem.

## Requirements

Rails 7.1 or newer, Ruby 3.1 or newer.

## License

MIT.
