# frozen_string_literal: true

require_relative "lib/soba/version"

Gem::Specification.new do |spec|
  spec.name = "soba"
  spec.version = Soba::VERSION
  spec.authors = ["douhashi"]
  spec.email = ["douhashi@example.com"]

  spec.summary = "GitHub to Claude Code workflow automation CLI"
  spec.description = "Soba is a CLI tool that automates the workflow between GitHub Issues and Claude Code, " \
                     "streamlining the development process from issue creation to pull request."
  spec.homepage = "https://github.com/douhashi/soba"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[test/ spec/ features/ .git .github appveyor Gemfile scripts/ .tmp/])
    end
  end
  spec.bindir = "bin"
  spec.executables = ["soba"]
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_runtime_dependency "gli", "~> 2.21"
  spec.add_runtime_dependency "dry-container", "~> 0.11"
  spec.add_runtime_dependency "dry-auto_inject", "~> 1.0"
  spec.add_runtime_dependency "faraday", "~> 2.9"
  spec.add_runtime_dependency "faraday-retry", "~> 2.2"
  spec.add_runtime_dependency "octokit", "~> 8.0"
  spec.add_runtime_dependency "concurrent-ruby", "~> 1.2"
  spec.add_runtime_dependency "semantic_logger", "~> 4.15"
  spec.add_runtime_dependency "dry-configurable", "~> 1.1"
  spec.add_runtime_dependency "activesupport", "~> 8.0"

  # Development dependencies are managed in Gemfile
end