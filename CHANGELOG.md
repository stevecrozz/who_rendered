# Changelog

## 0.1.0 (2026-09-11)

- Initial release. Adds `Rendered by: <file>:<line>` to the `Completed` log line, naming the
  `render`, `head`, or `redirect_to` call site that produced the response.
- Tested against Rails 7.1, 7.2, 8.0, 8.1 and `main`, with no version branching.
- Installs on `ActionController::Instrumentation` rather than on `ActionController::Base` and
  `ActionController::API`, so a gem that rebinds `append_info_to_payload` — lograge's
  `custom_payload` does — cannot end up as its own `super`.
