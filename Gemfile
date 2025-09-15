# frozen_string_literal: true

source "https://rubygems.org"

# CLI Framework
gem "gli", "~> 2.21"

# Dependency Injection
gem "dry-container", "~> 0.11"
gem "dry-auto_inject", "~> 1.0"

# HTTP Client & GitHub API
gem "faraday", "~> 2.9"
gem "faraday-retry", "~> 2.2"
gem "octokit", "~> 8.0"

# Concurrency
gem "concurrent-ruby", "~> 1.2"

# Logging
gem "semantic_logger", "~> 4.15"

# Configuration
gem "dry-configurable", "~> 1.1"

# Core Extensions (minimal)
gem "activesupport", "~> 8.0", require: false

group :development, :test do
  # Testing
  gem "rspec", "~> 3.12"
  gem "webmock", "~> 3.19"
  gem "vcr", "~> 6.2"
  gem "factory_bot", "~> 6.4"

  # Code Quality - Airbnb Style
  gem "rubocop-airbnb", "~> 6.0"
  gem "simplecov", "~> 0.22"

  # Security
  gem "bundler-audit", "~> 0.9"

  # Debugging
  gem "pry", "~> 0.14"
  gem "pry-byebug", "~> 3.10"
end