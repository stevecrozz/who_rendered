# frozen_string_literal: true

module WhoRendered
  # Selects the frames worth reporting from a raw call stack.
  #
  # Deliberately free of any Rails dependency: every root it needs is injected,
  # so the whole tier ladder is testable without booting anything.
  class CallSite
    # Rails renders from here when the action did not call render itself.
    IMPLICIT_RENDER_BASENAMES = ["implicit_render.rb", "basic_implicit_render.rb"].freeze

    # Anchored and greedy on purpose. The rubygems layout nests a "gems"
    # directory inside another (.../gems/3.4.0/gems/devise-4.9.4/...), so only
    # the rightmost match names the gem. Bundler's git layout
    # (.../bundler/gems/pundit-abc1234/...) falls out of the same pattern.
    GEM_PATH = %r{\A.*/gems/([^/]+)/(.+)\z}

    # Application subdirectories that are not really application code.
    EXCLUDED_APP_PREFIXES = ["vendor/", "bin/"].freeze

    # One reportable stack frame, formatted for humans.
    class Frame
      def initialize(location, display_path)
        @location = location
        @display_path = display_path
      end

      def to_s
        label = @location.label
        base = "#{@display_path}:#{@location.lineno}"
        label.nil? || label.empty? ? base : "#{base}:in '#{label}'"
      end
    end

    def initialize(app_root:, framework_roots:, own_root:)
      @app_root = normalize(app_root)
      @own_root = normalize(own_root)
      @framework_roots = Array(framework_roots).filter_map { |root| normalize(root) }
    end

    # True when Rails, not the application, called render.
    def implicit_render?(location)
      path = path_for(location)
      return false unless path

      IMPLICIT_RENDER_BASENAMES.include?(File.basename(path)) && framework?(path)
    end

    def frames(locations, limit: 1)
      candidates = locations.reject { |location| own?(path_for(location)) }
      return [] if candidates.empty?

      app = candidates.select { |location| app?(path_for(location)) }
      return build(app, limit) if app.any?

      external = candidates.reject { |location| framework?(path_for(location)) }
      return build(external, limit) if external.any?

      build(candidates, limit)
    end

    private
      def build(locations, limit)
        locations.first(limit).map { |location| Frame.new(location, display_path(path_for(location))) }
      end

      def display_path(path)
        return "?" unless path
        return path.delete_prefix(@app_root) if @app_root && path.start_with?(@app_root)

        match = GEM_PATH.match(path)
        match ? "#{match[1]}/#{match[2]}" : path
      end

      def app?(path)
        return false unless path && @app_root && path.start_with?(@app_root)

        relative = path.delete_prefix(@app_root)
        EXCLUDED_APP_PREFIXES.none? { |prefix| relative.start_with?(prefix) }
      end

      def framework?(path)
        return false unless path

        @framework_roots.any? { |root| path.start_with?(root) }
      end

      def own?(path)
        return false unless path && @own_root

        path.start_with?(@own_root)
      end

      def path_for(location)
        return nil unless location

        location.absolute_path || location.path
      end

      # Trailing separator so start_with? cannot match a sibling directory
      # whose name merely begins with the root's name.
      def normalize(root)
        return nil if root.nil? || root.to_s.empty?

        File.join(File.expand_path(root.to_s), "")
      end
  end
end
