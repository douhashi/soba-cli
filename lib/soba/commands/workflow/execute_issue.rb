# frozen_string_literal: true

require_relative '../../configuration'
require_relative '../../services/issue_processor'

module Soba
  module Commands
    module Workflow
      class ExecuteIssue
        attr_reader :configuration, :issue_processor

        def initialize(configuration: nil, issue_processor: nil)
          @configuration = configuration || Soba::Configuration.load!
          @issue_processor = issue_processor || Soba::Services::IssueProcessor.new
        end

        def execute(args, options = {})
          # Check if issue number is provided
          if args.blank?
            warn "Error: Issue number is required"
            return 1
          end

          issue_number = args[0]

          # Determine tmux mode based on priority
          use_tmux = determine_tmux_mode(options)

          # Display execution mode
          if use_tmux
            puts "Running issue ##{issue_number} with tmux"
          else
            if options["no-tmux"]
              puts "Running in direct mode (tmux disabled)"
            elsif ENV["SOBA_NO_TMUX"]
              puts "Running in direct mode (tmux disabled by environment variable)"
            else
              puts "Running in direct mode"
            end
          end

          begin
            # Process the issue
            @issue_processor.run(issue_number, use_tmux: use_tmux)
            0
          rescue StandardError => e
            warn "Error: #{e.message}"
            1
          end
        end

        private

        def determine_tmux_mode(options)
          # Priority: CLI option > Environment variable > Config file

          # 1. CLI option (highest priority)
          if options["no-tmux"]
            return false
          end

          # 2. Environment variable
          env_value = ENV["SOBA_NO_TMUX"]
          if env_value
            # true or 1 means disable tmux
            return !(env_value == "true" || env_value == "1")
          end

          # 3. Config file (lowest priority)
          config = @configuration.respond_to?(:config) ? @configuration.config : @configuration
          config.workflow.use_tmux
        end
      end
    end
  end
end