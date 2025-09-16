# frozen_string_literal: true

require_relative "../../services/issue_watcher"

module Soba
  module Commands
    module Issue
      class Watch
        include SemanticLogger::Loggable

        def initialize(github_client: nil)
          @github_client = github_client
        end

        def execute(repository:, interval:, config:)
          load_configuration(config) if config
          effective_interval = determine_interval(interval)

          validate_interval!(effective_interval)

          logger.info "Starting issue watch command",
                      repository: repository,
                      interval: effective_interval,
                      config: config

          watcher = create_watcher
          watcher.start(repository: repository, interval: effective_interval)
        rescue => e
          logger.error "Failed to start issue watcher",
                       error: e.message,
                       repository: repository

          raise
        end

        private

        def create_watcher
          if @github_client
            Services::IssueWatcher.new(github_client: @github_client)
          else
            Services::IssueWatcher.new
          end
        end

        def load_configuration(config_path)
          Soba::Configuration.load!(path: config_path)
        rescue => e
          logger.warn "Failed to load configuration",
                      path: config_path,
                      error: e.message
        end

        def determine_interval(cli_interval)
          # Priority: CLI argument > config file > default
          if cli_interval
            cli_interval
          elsif defined?(Soba::Configuration) && Soba::Configuration.config
            Soba::Configuration.config.workflow.interval
          else
            20
          end
        end

        def validate_interval!(interval)
          if interval < Services::IssueWatcher::MIN_INTERVAL
            raise ArgumentError, "Interval must be at least #{Services::IssueWatcher::MIN_INTERVAL} seconds"
          end
        end
      end
    end
  end
end