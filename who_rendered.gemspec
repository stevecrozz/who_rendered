# frozen_string_literal: true

require_relative "lib/who_rendered/version"

Gem::Specification.new do |spec|
  spec.name        = "who_rendered"
  spec.version     = WhoRendered::VERSION
  spec.authors     = ["Stephen Crosby"]
  spec.license     = "MIT"
  spec.summary     = "Find out who called render."
  spec.description = "Adds the file and line that produced a Rails response to the " \
                     "Completed log line, so an unexplained 403 names its own source."
  spec.homepage    = "https://github.com/stevecrozz/who_rendered"

  spec.required_ruby_version = ">= 3.1"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"]   = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir["lib/**/*.rb", "README.md", "LICENSE", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "actionpack", ">= 7.1"
  spec.add_dependency "railties", ">= 7.1"
end
