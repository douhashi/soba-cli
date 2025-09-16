# frozen_string_literal: true

require "gli"
require "dry-container"
require "dry-auto_inject"
require "faraday"
require "octokit"
require "concurrent"
require "semantic_logger"

require_relative "soba/version"

module Soba
  class Error < StandardError; end
  class ConfigError < Error; end
  class ConfigurationError < Error; end
  class GitHubError < Error; end
  class CommandError < Error; end

  module Domain; end
  module Services; end
  module Infrastructure; end
  module Commands
    module Issue; end
    module Config; end
  end

  SemanticLogger.default_level = :info
  SemanticLogger.add_appender(io: $stdout, formatter: :color)

  def self.logger
    @logger ||= SemanticLogger["Soba"]
  end
end

require_relative "soba/configuration"
require_relative "soba/config_loader"
require_relative "soba/container"
require_relative "soba/domain/issue"
require_relative "soba/services/issue_monitor"
require_relative "soba/services/workflow_blocking_checker"
require_relative "soba/infrastructure/errors"
require_relative "soba/infrastructure/github_client"