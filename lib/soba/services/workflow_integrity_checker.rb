# frozen_string_literal: true

require "logger"
require_relative "../configuration"

module Soba
  module Services
    class WorkflowIntegrityChecker
      ACTIVE_LABELS = %w(
        soba:queued
        soba:planning
        soba:doing
        soba:reviewing
        soba:revising
      ).freeze

      INTERMEDIATE_LABELS = %w(
        soba:review-requested
        soba:requires-changes
      ).freeze

      attr_reader :github_client, :logger

      def initialize(github_client:, logger: nil)
        @github_client = github_client
        @logger = logger || Logger.new(STDOUT)
      end

      def check_and_fix(repository, issues:, dry_run: false)
        logger.info("Checking workflow integrity for #{repository}")

        violations = detect_violations(issues)

        if violations.empty?
          logger.info("No workflow integrity violations found")
          return {
            violations_found: false,
            fixed_count: 0,
            violations: [],
            dry_run: dry_run,
          }
        end

        logger.warn("Found #{violations.size} workflow integrity violations")
        violations.each do |violation|
          logger.warn("  Issue ##{violation[:issue_number]}: #{violation[:label]} (#{violation[:action]})")
        end

        fixed_count = 0
        failed_fixes = 0

        if dry_run
          logger.info("Dry run mode - no fixes applied")
        else
          violations.each do |violation|
            if fix_violation(violation)
              fixed_count += 1
            else
              failed_fixes += 1
            end
          end
          if fixed_count > 0 || failed_fixes > 0
            logger.info("Fixed #{fixed_count} violations, #{failed_fixes} failed")
          end
        end

        {
          violations_found: true,
          fixed_count: fixed_count,
          failed_fixes: failed_fixes,
          violations: violations,
          dry_run: dry_run,
        }
      end

      private

      def detect_violations(issues)
        violations = []

        # Find all issues with active or intermediate labels
        active_issues = issues.select do |issue|
          labels = extract_label_names(issue.labels)
          (labels & (ACTIVE_LABELS + INTERMEDIATE_LABELS)).any?
        end

        return violations if active_issues.size <= 1

        # Multiple active issues detected - keep only the newest
        # Sort by created_at descending (newest first)
        sorted_issues = active_issues.sort_by { |issue| issue.created_at }.reverse
        newest_issue = sorted_issues.first

        # Mark all others as violations
        sorted_issues[1..-1].each do |issue|
          labels = extract_label_names(issue.labels)
          conflicting_label = labels.find { |l| (ACTIVE_LABELS + INTERMEDIATE_LABELS).include?(l) }

          violations << {
            issue_number: issue.number,
            label: conflicting_label,
            action: "removed",
            reason: "Multiple active issues detected, keeping newest (Issue ##{newest_issue.number})",
          }
        end

        violations
      end

      def fix_violation(violation)
        logger.info("Fixing violation: Issue ##{violation[:issue_number]} - removing #{violation[:label]}")

        # Determine the target label based on what's being removed
        target_label = determine_target_label(violation[:label])

        repository = Configuration.config.github.repository if defined?(Configuration)
        github_client.update_issue_labels(
          repository,
          violation[:issue_number],
          from: violation[:label],
          to: target_label
        )

        logger.info("Successfully fixed Issue ##{violation[:issue_number]}")
        true
      rescue => e
        logger.error("Failed to fix violation for Issue ##{violation[:issue_number]}: #{e.message}")
        false
      end

      def determine_target_label(from_label)
        # Most labels should revert to todo
        # Special cases can be handled here if needed
        case from_label
        when "soba:review-requested", "soba:requires-changes"
          "soba:ready"  # Review states go back to ready
        else
          "soba:todo"   # Active states go back to todo
        end
      end

      def extract_label_names(labels)
        labels.map do |label|
          if label.is_a?(Hash)
            label[:name] || label["name"]
          else
            label.name
          end
        end
      end
    end
  end
end