# frozen_string_literal: true

require_relative '../../configuration'
require_relative '../../services/auto_merge_service'

module Soba
  module Commands
    module Workflow
      class Merge
        def execute
          Soba::Configuration.load!

          config = Soba::Configuration.config
          unless config&.github&.repository
            puts "Error: GitHub repository is not configured"
            puts "Please run 'soba init' or set repository in .soba/config.yml"
            return
          end

          puts "Starting auto-merge process for repository: #{config.github.repository}"
          puts "-" * 50

          service = Soba::Services::AutoMergeService.new
          result = service.execute

          display_results(result)
        rescue => e
          puts "Error: #{e.message}"
          Soba.logger.error("Auto-merge failed", error: e.message, backtrace: e.backtrace.first(5))
        end

        private

        def display_results(result)
          if result[:merged_count] == 0 && result[:failed_count] == 0
            puts "No PRs with soba:lgtm label found"
            return
          end

          if result[:failed_count] == 0
            puts "Auto-merge completed successfully!"
          elsif result[:merged_count] == 0
            puts "Auto-merge failed for all PRs"
          else
            puts "Auto-merge completed with some failures"
          end

          puts ""
          puts "Summary:"
          puts "  Merged: #{result[:merged_count]} PRs"
          puts "  Failed: #{result[:failed_count]} PRs"

          if result[:merged_count] > 0
            puts ""
            puts "Merged PRs:"
            result[:details][:merged].each do |pr|
              puts "  - ##{pr[:number]}: #{pr[:title]}"
              puts "    SHA: #{pr[:sha]}" if pr[:sha]
            end
          end

          if result[:failed_count] > 0
            puts ""
            puts "Failed PRs:"
            result[:details][:failed].each do |pr|
              puts "  - ##{pr[:number]}: #{pr[:title]} - #{pr[:reason]}"
            end
          end
        end
      end
    end
  end
end