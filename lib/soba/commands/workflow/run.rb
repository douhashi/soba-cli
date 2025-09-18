# frozen_string_literal: true

require_relative '../../configuration'
require_relative '../../infrastructure/github_client'
require_relative '../../infrastructure/tmux_client'
require_relative '../../services/issue_watcher'
require_relative '../../services/issue_processor'
require_relative '../../services/workflow_executor'
require_relative '../../services/tmux_session_manager'
require_relative '../../services/workflow_blocking_checker'
require_relative '../../services/queueing_service'
require_relative '../../services/auto_merge_service'
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
            puts "Please run 'soba init' or set repository in .soba/config.yml"
            return
          end

          github_client = Soba::Infrastructure::GitHubClient.new
          tmux_client = Soba::Infrastructure::TmuxClient.new
          tmux_session_manager = Soba::Services::TmuxSessionManager.new(
            tmux_client: tmux_client
          )
          workflow_executor = Soba::Services::WorkflowExecutor.new(
            tmux_session_manager: tmux_session_manager
          )
          phase_strategy = Soba::Domain::PhaseStrategy.new
          issue_processor = Soba::Services::IssueProcessor.new(
            github_client: github_client,
            workflow_executor: workflow_executor,
            phase_strategy: phase_strategy,
            config: Soba::Configuration
          )
          blocking_checker = Soba::Services::WorkflowBlockingChecker.new(
            github_client: github_client
          )
          queueing_service = Soba::Services::QueueingService.new(
            github_client: github_client,
            blocking_checker: blocking_checker
          )
          auto_merge_service = Soba::Services::AutoMergeService.new

          repository = Soba::Configuration.config.github.repository
          interval = Soba::Configuration.config.workflow.interval || 10

          issue_watcher = Soba::Services::IssueWatcher.new(
            client: github_client,
            repository: repository,
            interval: interval
          )

          puts "Starting workflow monitor for #{repository}"
          puts "Polling interval: #{interval} seconds"
          puts "Auto-merge enabled: #{Soba::Configuration.config.workflow.auto_merge_enabled}"
          puts "Press Ctrl+C to stop"

          @running = true
          Signal.trap('INT') { @running = false }
          Signal.trap('TERM') { @running = false }

          while @running
            begin
              issues = issue_watcher.fetch_issues

              # Check for todo issues that need queueing
              todo_issues = issues.select do |issue|
                labels = issue.labels.map { |l| l[:name] }
                labels.include?('soba:todo')
              end

              # Queue todo issues if no active issues exist
              if todo_issues.any? && !blocking_checker.blocking?(repository, issues: issues)
                queued_issue = queueing_service.queue_next_issue(repository)
                if queued_issue
                  puts "\n✅ Queued Issue ##{queued_issue.number} for processing: #{queued_issue.title}"
                  # Refresh issues to include the new queued state
                  issues = issue_watcher.fetch_issues
                end
              end

              # Filter issues that need processing (including queued issues)
              processable_issues = issues.select do |issue|
                # Extract label names from hash array - labels are already hashes
                labels = issue.labels.map { |l| l[:name] }
                phase = phase_strategy.determine_phase(labels)
                # Process queued issues and other phases
                !phase.nil? && phase != :plan # Don't process todo directly, wait for queueing
              end

              # Sort by issue number (youngest first)
              processable_issues.sort_by!(&:number)

              # Check for approved PRs that need auto-merge (if enabled)
              if Soba::Configuration.config.workflow.auto_merge_enabled
                merge_result = auto_merge_service.execute
                if merge_result[:merged_count] > 0
                  puts "\n🎯 Auto-merged #{merge_result[:merged_count]} PR(s)"
                  merge_result[:details][:merged].each do |pr|
                    puts "  ✅ PR ##{pr[:number]}: #{pr[:title]}"
                  end
                end
                if merge_result[:failed_count] > 0
                  puts "\n⚠️  Failed to merge #{merge_result[:failed_count]} PR(s)"
                  merge_result[:details][:failed].each do |pr|
                    puts "  ❌ PR ##{pr[:number]}: #{pr[:reason]}"
                  end
                end
              end

              # Process the first issue if available
              if processable_issues.any?
                issue = processable_issues.first

                # Additional safety check: ensure no duplicate active issues before processing
                # This prevents race conditions when multiple workflow instances might be running
                active_labels = %w(soba:queued soba:planning soba:doing soba:reviewing soba:revising)
                intermediate_labels = %w(soba:review-requested soba:requires-changes)

                active_issues = issues.select do |i|
                  i_labels = i.labels.map { |l| l[:name] }
                  (i_labels & (active_labels + intermediate_labels)).any?
                end

                if active_issues.size > 1
                  puts "\n⚠️  Detected multiple active issues (#{active_issues.size}).\n" \
                       "  Skipping processing to avoid conflicts."
                  active_issues.each do |ai|
                    ai_labels = ai.labels.map { |l| l[:name] }
                    active_label = (ai_labels & (active_labels + intermediate_labels)).first
                    puts "  - Issue ##{ai.number}: #{active_label}"
                  end
                  puts "  Please resolve this manually or wait for the next cycle."
                  sleep(interval) if @running
                  next
                end

                puts "\n🚀 Processing Issue ##{issue.number}: #{issue.title}"

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
                    elsif result[:mode] == 'tmux'
                      # Display enhanced tmux information
                      if result[:tmux_info]
                        session_name = result[:tmux_info][:session] || result[:session_name]
                        puts "  📺 Session: #{session_name}"
                        puts "  💡 Monitor: soba monitor #{session_name}"
                        puts "  📁 Log: ~/.soba/logs/#{session_name}.log"
                      else
                        # Fallback to legacy output for backward compatibility
                        puts "  Tmux session started: #{result[:session_name]}" if result[:session_name]
                        puts "  You can attach with: tmux attach -t #{result[:session_name]}" if result[:session_name]
                      end
                    elsif result[:output]
                      puts "  Workflow output: #{result[:output].strip}"
                    end
                  end
                else
                  puts "  ❌ Failed: #{result[:error]}"
                end
              end

              sleep(interval) if @running
            rescue StandardError => e
              puts "Error: #{e.message}"
              puts e.backtrace.first(5).join("\n") if ENV['DEBUG']
              sleep(interval) if @running
            end
          end

          puts "\nWorkflow monitoring stopped"
        end
      end
    end
  end
end