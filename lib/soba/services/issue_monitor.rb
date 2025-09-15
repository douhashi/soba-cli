# frozen_string_literal: true

module Soba
  module Services
    class IssueMonitor
      def initialize(github_client: nil)
        @github_client = github_client || Infrastructure::GitHubClient.new
      end

      def monitor(repository:, interval: 60)
        Soba.logger.info("Starting issue monitor for #{repository}")

        loop do
          check_issues(repository)
          sleep(interval)
        end
      end

      private

      def check_issues(repository)
        issues = @github_client.issues(repository)
        Soba.logger.debug("Found #{issues.count} open issues")
      rescue => e
        Soba.logger.error("Failed to fetch issues: #{e.message}")
      end
    end
  end
end