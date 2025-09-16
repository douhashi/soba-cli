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
          Soba::Configuration.load! unless Soba::Configuration.config

          github_client = Soba::Infrastructure::GitHubClient.new
          workflow_executor = Soba::Services::WorkflowExecutor.new
          phase_strategy = Soba::Domain::PhaseStrategy.new
          issue_processor = Soba::Services::IssueProcessor.new(
            github_client: github_client,
            workflow_executor: workflow_executor,
            phase_strategy: phase_strategy,
            config: Soba::Configuration
          )

          issue_watcher = Soba::Services::IssueWatcher.new(
            client: github_client,
            repository: Soba::Configuration.config.github.repository,
            interval: Soba::Configuration.config.workflow.interval
          )

          puts "Starting workflow monitor for #{Soba::Configuration.config.github.repository}"
          puts "Polling interval: #{Soba::Configuration.config.workflow.interval} seconds"
          puts "Press Ctrl+C to stop"

          Signal.trap('INT') { issue_watcher.stop }
          Signal.trap('TERM') { issue_watcher.stop }

          while issue_watcher.running?
            begin
              issues = issue_watcher.fetch_issues

              # Filter issues that need processing
              processable_issues = issues.select do |issue|
                labels = issue[:labels].map { |l| l.is_a?(Hash) ? l[:name] : l }
                phase = phase_strategy.determine_phase(labels)
                !phase.nil?
              end

              # Sort by issue number (youngest first)
              processable_issues.sort_by! { |issue| issue[:number] }

              # Process the first issue if available
              if processable_issues.any?
                issue = processable_issues.first
                puts "\nProcessing Issue ##{issue[:number]}: #{issue[:title]}"

                result = issue_processor.process(issue)

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

              sleep(Soba::Configuration.config.workflow.interval)
            rescue StandardError => e
              puts "Error: #{e.message}"
              sleep(Soba::Configuration.config.workflow.interval)
            end
          end

          puts "\nWorkflow monitoring stopped"
        end
      end
    end
  end
end