# frozen_string_literal: true

module Soba
  module Services
    class ClosedIssueWindowCleaner
      attr_reader :github_client, :tmux_client, :logger

      def initialize(github_client:, tmux_client:, logger:)
        @github_client = github_client
        @tmux_client = tmux_client
        @logger = logger
        @last_cleanup_time = nil
        @repository = nil
      end

      def clean(session_name)
        logger.debug("Cleaning up windows for closed issues in session: #{session_name}")

        begin
          closed_issues = fetch_closed_issues
          if closed_issues.empty?
            logger.debug('No closed issues found')
            return
          end

          logger.debug("Found #{closed_issues.size} closed issues")

          windows = list_tmux_windows(session_name)
          return if windows.nil?

          removed_count = 0
          closed_issues.each do |issue|
            window_name = "issue-#{issue.number}"
            if windows.include?(window_name)
              if remove_window(session_name, window_name, issue)
                removed_count += 1
              end
            end
          end

          logger.debug("Cleanup completed for #{session_name}: removed #{removed_count} windows")
        rescue StandardError => e
          logger.error("Unexpected error during cleanup: #{e.message}")
        end
      end

      def should_clean?
        return false unless config.workflow.closed_issue_cleanup_enabled

        if @last_cleanup_time.nil?
          @last_cleanup_time = Time.now
          return true
        end

        time_since_last = Time.now - @last_cleanup_time
        if time_since_last >= config.workflow.closed_issue_cleanup_interval
          @last_cleanup_time = Time.now
          return true
        end

        false
      end

      private

      def config
        @config ||= Soba::Configuration.config
      end

      def fetch_closed_issues
        repository = config.github.repository || ENV['GITHUB_REPOSITORY']
        github_client.fetch_closed_issues(repository)
      rescue StandardError => e
        logger.error("Failed to fetch closed issues: #{e.message}")
        []
      end

      def list_tmux_windows(session_name)
        tmux_client.list_windows(session_name)
      rescue StandardError => e
        logger.error("Failed to list tmux windows: #{e.message}")
        nil
      end

      def remove_window(session_name, window_name, issue)
        if tmux_client.kill_window(session_name, window_name)
          logger.info("Removed window: #{window_name} (Issue ##{issue.number}: #{issue.title})")
          true
        else
          logger.warn("Failed to remove window: #{window_name}")
          false
        end
      end
    end
  end
end