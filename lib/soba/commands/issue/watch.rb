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
          load_configuration(config)
          effective_interval = determine_interval(interval)
          effective_repository = determine_repository(repository)

          validate_interval!(effective_interval)
          validate_repository!(effective_repository)

          logger.info "Starting issue watch command",
                      repository: effective_repository,
                      interval: effective_interval,
                      config: config

          watcher = create_watcher
          watcher.start(repository: effective_repository, interval: effective_interval)
        rescue => e
          logger.error "Failed to start issue watcher",
                       error: e.message,
                       repository: effective_repository

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
          if config_path
            Soba::Configuration.load!(path: config_path)
          else
            # Load from default location
            Soba::Configuration.load!
          end
        rescue => e
          logger.debug "Configuration loading failed",
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

        def determine_repository(cli_repository)
          # Priority: CLI argument > config file
          if cli_repository.present?
            cli_repository
          elsif defined?(Soba::Configuration) && Soba::Configuration.config
            Soba::Configuration.config.github.repository
          else
            nil
          end
        end

        def validate_interval!(interval)
          if interval < Services::IssueWatcher::MIN_INTERVAL
            message = "Interval must be at least #{Services::IssueWatcher::MIN_INTERVAL} seconds"
            warn "Error: #{message}"
            raise ArgumentError, message
          end
        end

        def validate_repository!(repository)
          if repository.blank?
            message = "Repository is required. Specify via argument or config file"
            warn "Error: #{message}"
            raise ArgumentError, message
          end
        end
      end
    end
  end
end