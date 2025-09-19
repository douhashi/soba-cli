# frozen_string_literal: true

require_relative 'lib/soba/version'

Gem::Specification.new do |spec|
  spec.name          = 'soba'
  spec.version       = Soba::VERSION
  spec.authors       = ['douhashi']
  spec.email         = ['soba@example.com']

  spec.summary       = 'GitHub Issue駆動の自動開発CLI'
  spec.description   = 'sobaはGitHub Issueを中心とした自動開発ワークフローを実現するCLIツールです。' \
                       'Issueの管理、開発フローの自動化、ブランチ管理などを提供します。'
  spec.homepage      = 'https://github.com/douhashi/soba'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.0.0'

  spec.metadata['allowed_push_host'] = 'TODO: Set to your gem server'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/douhashi/soba'
  spec.metadata['changelog_uri'] = 'https://github.com/douhashi/soba/blob/main/CHANGELOG.md'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w(spec/ test/ tests/ features/ .git .github appveyor Gemfile))
    end
  end
  spec.bindir        = 'bin'
  spec.executables   = spec.files.grep(%r{\Abin/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Runtime dependencies
  spec.add_runtime_dependency 'gli', '~> 2.21'
  spec.add_runtime_dependency 'dry-container', '~> 0.11'
  spec.add_runtime_dependency 'dry-auto_inject', '~> 1.0'
  spec.add_runtime_dependency 'faraday', '~> 2.9'
  spec.add_runtime_dependency 'faraday-retry', '~> 2.2'
  spec.add_runtime_dependency 'octokit', '~> 8.0'
  spec.add_runtime_dependency 'concurrent-ruby', '~> 1.2'
  spec.add_runtime_dependency 'semantic_logger', '~> 4.15'
  spec.add_runtime_dependency 'dry-configurable', '~> 1.1'
  spec.add_runtime_dependency 'activesupport', '~> 8.0'

  # Development dependencies
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.12'
  spec.add_development_dependency 'webmock', '~> 3.19'
  spec.add_development_dependency 'vcr', '~> 6.2'
  spec.add_development_dependency 'factory_bot', '~> 6.4'
  spec.add_development_dependency 'rubocop-airbnb', '~> 6.0'
  spec.add_development_dependency 'simplecov', '~> 0.22'
  spec.add_development_dependency 'bundler-audit', '~> 0.9'
  spec.add_development_dependency 'pry', '~> 0.14'
  spec.add_development_dependency 'pry-byebug', '~> 3.10'

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end