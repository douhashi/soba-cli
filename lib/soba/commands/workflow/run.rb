# frozen_string_literal: true

require_relative '../../configuration'
require_relative '../../infrastructure/github_client'
require_relative '../../services/issue_watcher'
require_relative '../../services/issue_processor'
require_relative '../../services/workflow_executor'
require_relative '../../domain/phase_strategy'

module Soba
  module Commands
    module Workflow
      class Run
        def execute(global_options, _options)
          Soba::Configuration.load!

          config = Soba::Configuration.config
          unless config&.github&.repository
            puts "Error: GitHub repository is not configured"
            puts "Please run 'soba init' or set repository in .osoba/config.yml"
            return
          end

          github_client = Soba::Infrastructure::GitHubClient.new
          workflow_executor = Soba::Services::WorkflowExecutor.new
          phase_strategy = Soba::Domain::PhaseStrategy.new
          issue_processor = Soba::Services::IssueProcessor.new(
            github_client: github_client,
            workflow_executor: workflow_executor,
            phase_strategy: phase_strategy,
            config: Soba::Configuration
          )

          repository = Soba::Configuration.config.github.repository
          interval = Soba::Configuration.config.workflow.interval

          issue_watcher = Soba::Services::IssueWatcher.new(
            client: github_client,
            repository: repository,
            interval: interval
          )

          puts "Starting workflow monitor for #{repository}"
          puts "Polling interval: #{interval} seconds"
          puts "Press Ctrl+C to stop"

          @running = true
          Signal.trap('INT') { @running = false }
          Signal.trap('TERM') { @running = false }

          while @running
            begin
              issues = issue_watcher.fetch_issues

              # Filter issues that need processing
              processable_issues = issues.select do |issue|
                # Extract label names from hash array
                labels = issue.labels.map { |l| l[:name] }
                phase = phase_strategy.determine_phase(labels)
                !phase.nil?
              end

              # Sort by issue number (youngest first)
              processable_issues.sort_by!(&:number)

              # Process the first issue if available
              if processable_issues.any?
                issue = processable_issues.first
                puts "\nProcessing Issue ##{issue.number}: #{issue.title}"

                # Convert Domain::Issue to Hash for issue_processor
                # Extract label names for issue_processor
                issue_hash = {
                  number: issue.number,
                  title: issue.title,
                  labels: issue.labels.map { |l| l[:name] },
                }

                result = issue_processor.process(issue_hash)

                if result[:success]
                  if result[:skipped]
                    puts "  Skipped: #{result[:reason]}"
                  else
                    puts "  Phase: #{result[:phase]}"
                    puts "  Label updated: #{result[:label_updated]}"
                    if result[:workflow_skipped]
                      puts "  Workflow skipped: #{result[:reason]}"
                    elsif result[:output]
                      puts "  Workflow output: #{result[:output].strip}"
                    end
                  end
                else
                  puts "  Failed: #{result[:error]}"
                end
              end

              sleep(Soba::Configuration.config.workflow.interval) if @running
            rescue StandardError => e
              puts "Error: #{e.message}"
              sleep(Soba::Configuration.config.workflow.interval) if @running
            end
          end

          puts "\nWorkflow monitoring stopped"
        end
      end
    end
  end
end