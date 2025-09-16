# frozen_string_literal: true

require "concurrent-ruby"
require "time"

module Soba
  module Services
    class IssueWatcher
      include SemanticLogger::Loggable

      MIN_INTERVAL = 10

      def initialize(client: nil, repository: nil, interval: nil)
        @github_client = client || Infrastructure::GitHubClient.new
        @repository = repository
        @interval = interval
        @running = Concurrent::AtomicBoolean.new(false)
        @mutex = Mutex.new
        @signal_received = false
      end

      def start(repository:, interval: 20)
        validate_interval!(interval)

        logger.info "Starting issue watcher", repository: repository, interval: interval
        @running.make_true
        @repository = repository
        @interval = interval

        setup_signal_handlers
        display_header

        execution_count = run_monitoring_loop

        # Show graceful shutdown message
        if @signal_received
          puts "\n✅ Issue watcher stopped gracefully (#{execution_count} executions)"
        else
          puts "\n✅ Issue watcher stopped successfully (#{execution_count} executions)"
          logger.info "Issue watcher stopped", executions: execution_count
        end
      ensure
        @running.make_false
      end

      def stop
        @running.make_false
      end

      def running?
        @running.value
      end

      def fetch_issues(state: "open")
        @github_client.issues(@repository, state: state)
      end

      private

      def validate_interval!(interval)
        if interval < MIN_INTERVAL
          raise ArgumentError, "Interval must be at least #{MIN_INTERVAL} seconds to avoid rate limiting"
        end
      end

      def setup_signal_handlers
        %w(INT TERM).each do |signal|
          Signal.trap(signal) do
            @signal_received = true
            puts "\n\n🛑 Received #{signal} signal, shutting down gracefully..."
            @running.make_false
          end
        end
      end

      def run_monitoring_loop
        execution_count = 0

        while running?
          @mutex.synchronize do
            fetch_and_display_issues
            execution_count += 1
          end

          break unless running?
          sleep(@interval)
        end

        execution_count
      rescue => e
        # Skip logging if interrupted by signal
        unless @signal_received
          logger.error "Unexpected error in monitoring loop", error: e.message
          raise
        end
        execution_count
      end

      def fetch_and_display_issues
        issues = @github_client.issues(@repository, state: "open")

        display_issues(issues)
        log_execution_summary(issues)
      rescue Soba::Infrastructure::NetworkError => e
        logger.error "Failed to fetch issues", error: e.message, repository: @repository
        puts "\n⚠️  Network error: #{e.message}"
      rescue Soba::Infrastructure::RateLimitExceeded => e
        logger.warn "Rate limit exceeded", error: e.message
        puts "\n⚠️  Rate limit exceeded. Waiting before retry..."
        handle_rate_limit
      rescue => e
        logger.error "Unexpected error fetching issues", error: e.message, class: e.class.name
        puts "\n❌ Error: #{e.message}"
      end

      def display_header
        puts "\n" + "=" * 80
        puts "📋 Issue Watcher Started"
        puts "Repository: #{@repository}"
        puts "Interval: #{@interval} seconds"
        puts "Press Ctrl+C to stop"
        puts "=" * 80
        puts
      end

      def display_issues(issues)
        timestamp = Time.now.strftime("%Y-%m-%d %H:%M:%S")
        puts "\n[#{timestamp}] Found #{issues.count} open issues"

        if issues.empty?
          puts "  No open issues found."
          return
        end

        puts "\n  %-6s | %-50s | %-20s | %s" % ["#", "Title", "Labels", "Updated"]
        puts "  #{"-" * 90}"

        issues.each do |issue|
          display_issue_row(issue)
        end
        puts
      end

      def display_issue_row(issue)
        number = "##{issue.number}"
        title = truncate(issue.title, 50)
        labels = format_labels(issue.labels)
        updated = format_time(issue.updated_at)

        puts "  %-6s | %-50s | %-20s | %s" % [number, title, labels, updated]
      end

      def format_labels(labels)
        return "-" if labels.empty?

        label_names = labels.map { |label| label[:name] }
        truncate(label_names.join(", "), 20)
      end

      def format_time(time)
        return "-" unless time

        diff = Time.now - time
        case diff
        when 0...3600
          "#{(diff / 60).to_i} mins ago"
        when 3600...86400
          "#{(diff / 3600).to_i} hours ago"
        else
          "#{(diff / 86400).to_i} days ago"
        end
      end

      def truncate(text, max_length)
        return text if text.length <= max_length

        "#{text[0...max_length - 3]}..."
      end

      def log_execution_summary(issues)
        logger.debug "Issue fetch completed",
                     repository: @repository,
                     issue_count: issues.count,
                     timestamp: Time.now.iso8601
      end

      def handle_rate_limit
        # Wait for 1 minute before retrying
        sleep(60) if running?
      end
    end
  end
end