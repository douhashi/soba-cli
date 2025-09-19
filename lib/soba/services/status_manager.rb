# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'time'

module Soba
  module Services
    class StatusManager
      attr_reader :status_file

      def initialize(status_file)
        @status_file = status_file
      end

      def write(data)
        dir = File.dirname(status_file)
        FileUtils.mkdir_p(dir) unless File.directory?(dir)

        # Atomic write using temp file
        temp_file = "#{status_file}.tmp"
        File.write(temp_file, JSON.pretty_generate(data))
        File.rename(temp_file, status_file)
      rescue StandardError => e
        # Clean up temp file if something goes wrong
        FileUtils.rm_f(temp_file) if defined?(temp_file)
        raise e
      end

      def read
        return nil unless File.exist?(status_file)

        content = File.read(status_file)
        return nil if content.empty?

        JSON.parse(content, symbolize_names: true)
      rescue JSON::ParserError, StandardError
        nil
      end

      def update_current_issue(issue_number, phase)
        data = read || {}
        data[:current_issue] = {
          number: issue_number,
          phase: phase,
          started_at: Time.now.iso8601,
        }
        write(data)
      end

      def update_last_processed
        data = read || {}
        if data[:current_issue]
          data[:last_processed] = {
            number: data[:current_issue][:number],
            completed_at: Time.now.iso8601,
          }
          data.delete(:current_issue)
        end
        write(data)
      end

      def update_memory(memory_mb)
        data = read || {}
        data[:memory_mb] = memory_mb
        write(data)
      end

      def clear
        FileUtils.rm_f(status_file)
      end
    end
  end
end