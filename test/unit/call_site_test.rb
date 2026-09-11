# frozen_string_literal: true

require "unit_helper"

class CallSiteTest < Minitest::Test
  APP_ROOT = "/srv/myapp"
  GEM_DIR = "/usr/lib/ruby/gems/3.4.0/gems"
  RAILS_ROOT = "#{GEM_DIR}/actionpack-8.1.3"
  ACTIVESUPPORT_ROOT = "#{GEM_DIR}/activesupport-8.1.3"
  OWN_ROOT = "#{GEM_DIR}/who_rendered-0.1.0/lib/who_rendered"

  # Stands in for Thread::Backtrace::Location.
  Loc = Struct.new(:absolute_path, :lineno, :label) do
    def path
      absolute_path
    end
  end

  def call_site(app_root: APP_ROOT)
    WhoRendered::CallSite.new(
      app_root: app_root,
      framework_roots: [RAILS_ROOT, ACTIVESUPPORT_ROOT],
      own_root: OWN_ROOT
    )
  end

  def app_loc(relative, lineno, label)
    Loc.new(File.join(APP_ROOT, relative), lineno, label)
  end

  def test_selects_the_innermost_app_frame
    frames = call_site.frames([
      Loc.new("#{RAILS_ROOT}/lib/action_controller/metal/head.rb", 35, "head"),
      app_loc("app/controllers/concerns/admin_gate.rb", 14, "require_admin"),
      Loc.new("#{ACTIVESUPPORT_ROOT}/lib/active_support/callbacks.rb", 130, "run_callbacks"),
      app_loc("app/controllers/admin/reports_controller.rb", 3, "index")
    ], limit: 1)

    assert_equal ["app/controllers/concerns/admin_gate.rb:14:in 'require_admin'"], frames.map(&:to_s)
  end

  def test_returns_app_frames_innermost_first_up_to_the_limit
    frames = call_site.frames([
      app_loc("app/controllers/application_controller.rb", 88, "render_403"),
      app_loc("app/controllers/concerns/admin_gate.rb", 14, "require_admin"),
      app_loc("app/controllers/admin/reports_controller.rb", 3, "index"),
      app_loc("app/controllers/extra.rb", 9, "extra")
    ], limit: 3)

    assert_equal [
      "app/controllers/application_controller.rb:88:in 'render_403'",
      "app/controllers/concerns/admin_gate.rb:14:in 'require_admin'",
      "app/controllers/admin/reports_controller.rb:3:in 'index'"
    ], frames.map(&:to_s)
  end

  def test_ignores_vendor_and_bin_frames_inside_the_app
    frames = call_site.frames([
      app_loc("vendor/bundle/thing.rb", 5, "thing"),
      app_loc("bin/rails", 4, "<main>"),
      app_loc("app/controllers/posts_controller.rb", 7, "show")
    ], limit: 1)

    assert_equal ["app/controllers/posts_controller.rb:7:in 'show'"], frames.map(&:to_s)
  end

  # The rubygems layout nests one "gems" directory inside another, so a naive
  # unanchored match captures the Ruby ABI version instead of the gem.
  def test_falls_back_to_the_innermost_gem_frame_labelled_with_name_and_version
    frames = call_site.frames([
      Loc.new("#{RAILS_ROOT}/lib/action_controller/metal/head.rb", 35, "head"),
      Loc.new("#{GEM_DIR}/devise-4.9.4/lib/devise/controllers/helpers.rb", 99, "authenticate_user!"),
      Loc.new("#{ACTIVESUPPORT_ROOT}/lib/active_support/callbacks.rb", 130, "run_callbacks")
    ], limit: 1)

    assert_equal ["devise-4.9.4/lib/devise/controllers/helpers.rb:99:in 'authenticate_user!'"],
      frames.map(&:to_s)
  end

  def test_labels_git_sourced_gem_frames
    frames = call_site.frames([
      Loc.new("/srv/bundle/bundler/gems/pundit-abc1234/lib/pundit.rb", 12, "authorize")
    ], limit: 1)

    assert_equal ["pundit-abc1234/lib/pundit.rb:12:in 'authorize'"], frames.map(&:to_s)
  end

  def test_falls_back_to_the_raw_innermost_frame_when_everything_is_framework
    frames = call_site.frames([
      Loc.new("#{RAILS_ROOT}/lib/action_controller/metal/head.rb", 35, "head"),
      Loc.new("#{ACTIVESUPPORT_ROOT}/lib/active_support/callbacks.rb", 130, "run_callbacks")
    ], limit: 1)

    assert_equal ["actionpack-8.1.3/lib/action_controller/metal/head.rb:35:in 'head'"],
      frames.map(&:to_s)
  end

  # Required for anyone running Rails as a path: or git: dependency, where no
  # /gems/ segment appears in the framework's paths at all.
  def test_identifies_framework_frames_outside_any_gems_directory
    site = WhoRendered::CallSite.new(
      app_root: APP_ROOT,
      framework_roots: ["/home/dev/Projects/rails/actionpack"],
      own_root: OWN_ROOT
    )

    frames = site.frames([
      Loc.new("/home/dev/Projects/rails/actionpack/lib/action_controller/metal/head.rb", 35, "head"),
      Loc.new("#{GEM_DIR}/devise-4.9.4/lib/devise.rb", 99, "authenticate_user!")
    ], limit: 1)

    assert_equal ["devise-4.9.4/lib/devise.rb:99:in 'authenticate_user!'"], frames.map(&:to_s)
  end

  def test_skips_the_gems_own_frames
    frames = call_site.frames([
      Loc.new("#{OWN_ROOT}/controller_hooks.rb", 12, "render"),
      app_loc("app/controllers/posts_controller.rb", 7, "show")
    ], limit: 1)

    assert_equal ["app/controllers/posts_controller.rb:7:in 'show'"], frames.map(&:to_s)
  end

  def test_returns_empty_for_an_empty_stack
    assert_empty call_site.frames([], limit: 1)
  end

  def test_works_when_there_is_no_app_root
    frames = call_site(app_root: nil).frames([
      Loc.new("#{GEM_DIR}/devise-4.9.4/lib/devise.rb", 5, "call")
    ], limit: 1)

    assert_equal ["devise-4.9.4/lib/devise.rb:5:in 'call'"], frames.map(&:to_s)
  end

  def test_omits_the_method_name_when_the_label_is_missing
    frames = call_site.frames([app_loc("config/routes.rb", 2, nil)], limit: 1)

    assert_equal ["config/routes.rb:2"], frames.map(&:to_s)
  end

  def test_recognises_the_implicit_render_call_sites
    assert call_site.implicit_render?(
      Loc.new("#{RAILS_ROOT}/lib/action_controller/metal/implicit_render.rb", 36, "default_render")
    )
    assert call_site.implicit_render?(
      Loc.new("#{RAILS_ROOT}/lib/action_controller/metal/basic_implicit_render.rb", 8, "send_action")
    )
  end

  def test_does_not_treat_app_or_gem_frames_as_implicit_render
    refute call_site.implicit_render?(app_loc("app/controllers/posts_controller.rb", 7, "show"))
    refute call_site.implicit_render?(
      Loc.new("#{GEM_DIR}/other-1.0/lib/implicit_render.rb", 2, "default_render")
    )
    refute call_site.implicit_render?(nil)
  end
end
