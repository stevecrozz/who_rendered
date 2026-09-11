# frozen_string_literal: true

require "rails/railtie"
require "who_rendered/controller_hooks"
require "who_rendered/payload"
require "who_rendered/log_subscriber"

module WhoRendered
  class Railtie < ::Rails::Railtie
    config.who_rendered = WhoRendered.config

    initializer "who_rendered.install" do
      ActiveSupport.on_load(:action_controller_base) do
        prepend WhoRendered::ControllerHooks

        # ActionController::LogSubscriber calls this literally as
        # ActionController::Base.log_process_action, even for API controllers,
        # so Base is the only place it needs installing.
        singleton_class.prepend WhoRendered::Payload::ClassMethods
      end

      ActiveSupport.on_load(:action_controller_api) do
        prepend WhoRendered::ControllerHooks
      end

      # Payload goes onto ActionController::Instrumentation, where
      # append_info_to_payload is actually defined, rather than onto Base and API.
      # Instrumentation is in the ancestors of both, so one prepend covers them —
      # but the reason it must not be Base is compatibility, not brevity.
      #
      # lograge's custom_payload support does
      # `m = Klass.instance_method(:append_info_to_payload)` and then
      # `define_method(:append_info_to_payload) { m.bind(self).call(...) }` on
      # ActionController::Base. Prepended to Base, Payload is the topmost owner, so
      # that captures Payload itself and redefines the method Payload's super then
      # resolves to: unbounded mutual recursion, SystemStackError on every request,
      # and WhoRendered.safely cannot catch it because SystemStackError is not a
      # StandardError.
      #
      # Prepended to Instrumentation, Payload sits below Base in the ancestors, so a
      # method defined directly on Base wins dispatch and Payload's super continues
      # downward into Instrumentation. The cycle cannot form, in either installation
      # order.
      #
      # This relies on a prepend to a module propagating into the classes that already
      # include it, since Base has usually included Instrumentation by the time this
      # runs. ThirdPartyPayloadHookTest asserts Payload really is in the ancestors of
      # both Base and API, so a Ruby where that does not hold fails loudly.
      ActiveSupport.on_load(:action_controller, run_once: true) do
        ActionController::Instrumentation.prepend WhoRendered::Payload
      end

      # Plain Notifications rather than the gem's LogSubscriber, because
      # ActiveSupport::LogSubscriber#call skips the event when it has no logger,
      # and this clear must not depend on logging at all. See
      # WhoRendered::Payload.clear_source for why it happens here.
      ActiveSupport::Notifications.subscribe("start_processing.action_controller") do
        WhoRendered.safely { WhoRendered::Payload.clear_source }
      end

      # ActionController requires and attaches its own LogSubscriber from the top
      # of both action_controller/base.rb and action_controller/api.rb, and runs
      # the :action_controller load hook at the end of those files. Subscribing
      # from that hook therefore puts us after ActionController::LogSubscriber, so
      # these lines print after the Completed line. Attaching in the initializer
      # body instead would subscribe us first, because ActionController::Base has
      # not been loaded at that point. run_once keeps an app that loads both Base
      # and API from attaching twice.
      ActiveSupport.on_load(:action_controller, run_once: true) do
        WhoRendered::LogSubscriber.attach_to :action_controller
      end
    end
  end
end
