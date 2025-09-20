# frozen_string_literal: true

require 'fileutils'
require_relative '../configuration'
require_relative '../infrastructure/github_client'
require_relative '../infrastructure/tmux_client'
require_relative '../services/issue_watcher'
require_relative '../services/issue_processor'
require_relative '../services/workflow_executor'
require_relative '../services/tmux_session_manager'
require_relative '../services/workflow_blocking_checker'
require_relative '../services/queueing_service'
require_relative '../services/auto_merge_service'
require_relative '../services/closed_issue_window_cleaner'
require_relative '../domain/phase_strategy'
require_relative '../services/pid_manager'
require_relative '../services/daemon_service'
require_relative '../services/status_manager'
require_relative '../services/process_info'

module Soba
  module Commands
    class Start
      attr_reader :configuration, :issue_processor

      def initialize(configuration: nil, issue_processor: nil)
        @configuration = configuration
        @issue_processor = issue_processor
      end

      def execute(global_options, options, args)
        # Handle deprecated --foreground option
        if options[:foreground]
          puts "DEPRECATED: The --foreground option is now the default behavior."
          puts "This option will be removed in a future version."
          options.delete(:foreground)
        end

        if args.empty?
          # ワークフロー実行モード（既存のworkflow runの動作）
          execute_workflow(global_options, options)
        else
          # 単一Issue実行モード（既存のworkflow execute_issueの動作）
          # 早期引数チェック（設定読み込み前）
          if args[0].blank? || args[0].strip.empty?
            warn "Error: Issue number is required"
            return 1
          end
          execute_issue(args, options)
        end
      end

      private

      def log_output(message, options, daemon_service = nil)
        if options[:daemon]
          daemon_service&.log(message)
        else
          puts message
        end
      end

      def execute_workflow(global_options, options)
        # Daemon mode setup
        if options[:daemon]
          # Allow test environment to override PID file path
          pid_file = ENV['SOBA_TEST_PID_FILE'] || File.expand_path('~/.soba/soba.pid')
          log_file = ENV['SOBA_TEST_LOG_FILE'] || File.expand_path('~/.soba/logs/daemon.log')

          pid_manager = Soba::Services::PidManager.new(pid_file)
          daemon_service = Soba::Services::DaemonService.new(
            pid_manager: pid_manager,
            log_file: log_file
          )

          # Check if already running
          if daemon_service.already_running?
            pid = pid_manager.read
            puts "Daemon is already running (PID: #{pid})"
            puts "Use 'soba stop' to stop the daemon or 'soba status' to check status"
            return 1
          end

          # Daemonize
          puts "Starting daemon..."
          daemon_service.daemonize!

          # Log startup
          daemon_service.log("Daemon started successfully (PID: #{Process.pid})")

          # Setup signal handlers for daemon
          daemon_service.setup_signal_handlers do
            @running = false
          end
        end

        Soba::Configuration.load!

        config = Soba::Configuration.config

        # Initialize status manager (allow test environment to override path)
        status_file = ENV['SOBA_TEST_STATUS_FILE'] || File.expand_path('~/.soba/status.json')
        status_manager = Soba::Services::StatusManager.new(status_file)

        unless config&.github&.repository
          message = "Error: GitHub repository is not configured\n" \
                    "Please run 'soba init' or set repository in .soba/config.yml"
          if options[:foreground]
            puts message
          else
            daemon_service.log(message) if defined?(daemon_service)
          end
          return 1
        end

        github_client = Soba::Infrastructure::GitHubClient.new
        tmux_client = Soba::Infrastructure::TmuxClient.new
        tmux_session_manager = Soba::Services::TmuxSessionManager.new(
          tmux_client: tmux_client
        )

        # Create empty tmux session at startup
        session_result = tmux_session_manager.find_or_create_repository_session
        if session_result[:success]
          if session_result[:created]
            message = "Created tmux session: #{session_result[:session_name]}"
          else
            message = "Using existing tmux session: #{session_result[:session_name]}"
          end
          if options[:daemon]
            daemon_service.log(message) if defined?(daemon_service)
          else
            puts message
          end
        end
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
        cleanup_logger = Logger.new(STDOUT)
        cleanup_logger.level = Logger::INFO
        cleaner_service = Soba::Services::ClosedIssueWindowCleaner.new(
          github_client: github_client,
          tmux_client: tmux_client,
          logger: cleanup_logger
        )

        repository = Soba::Configuration.config.github.repository
        interval = Soba::Configuration.config.workflow.interval || 10

        issue_watcher = Soba::Services::IssueWatcher.new(
          client: github_client,
          repository: repository,
          interval: interval
        )

        # Log or print based on mode
        startup_message = [
          "Starting workflow monitor for #{repository}",
          "Polling interval: #{interval} seconds",
          "Auto-merge enabled: #{Soba::Configuration.config.workflow.auto_merge_enabled}",
          "Closed issue cleanup enabled: #{Soba::Configuration.config.workflow.closed_issue_cleanup_enabled}",
        ]

        if options[:daemon]
          startup_message.each { |msg| daemon_service.log(msg) if defined?(daemon_service) }
        else
          startup_message.each { |msg| puts msg }
          puts "Press Ctrl+C to stop"
        end

        @running = true
        unless options[:daemon]
          Signal.trap('INT') { @running = false }
          Signal.trap('TERM') { @running = false }
        end

        while @running
          # Check for graceful shutdown request
          stopping_file = File.expand_path('~/.soba/stopping')
          if File.exist?(stopping_file)
            message = "Graceful shutdown requested, completing current workflow..."
            log_output(message, options, daemon_service)
            @running = false
            FileUtils.rm_f(stopping_file)
            next
          end

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

            # Update memory usage periodically
            if Process.pid
              process_info = Soba::Services::ProcessInfo.new(Process.pid)
              memory_mb = process_info.memory_usage_mb
              status_manager.update_memory(memory_mb) if memory_mb
            end

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

            # Cleanup closed issue windows (if enabled and interval has passed)
            if cleaner_service.should_clean?
              timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
              puts "[#{timestamp}] Running closed issue cleanup..."
              active_sessions = tmux_client.list_soba_sessions
              active_sessions.each do |session|
                cleaner_service.clean(session)
              end
              puts "[#{timestamp}] Closed issue cleanup completed for #{active_sessions.size} session(s)"
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

              # Update status with current issue
              labels = issue.labels.map { |l| l[:name] }
              phase_label = labels.find { |l| l.start_with?('soba:') }
              status_manager.update_current_issue(issue.number, phase_label) if phase_label

              # Convert Domain::Issue to Hash for issue_processor
              # Extract label names for issue_processor
              issue_hash = {
                number: issue.number,
                title: issue.title,
                labels: issue.labels.map { |l| l[:name] },
              }

              result = issue_processor.process(issue_hash)

              # Mark as last processed when done
              if result && result[:success]
                status_manager.update_last_processed
              end

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

      def execute_issue(args, options = {})
        # Check if issue number is provided
        if args.empty? || args[0].nil? || args[0].empty? || args[0].strip.empty?
          warn "Error: Issue number is required"
          return 1
        end

        # Initialize configuration and issue processor if needed
        @configuration ||= Soba::Configuration.load!
        @issue_processor ||= Soba::Services::IssueProcessor.new

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