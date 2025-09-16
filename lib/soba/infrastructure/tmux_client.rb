# frozen_string_literal: true

require 'open3'

module Soba
  module Infrastructure
    class TmuxError < StandardError; end

    class TmuxClient
      def create_session(session_name)
        _stdout, _stderr, status = execute_tmux_command('new-session', '-d', '-s', session_name)
        status.exitstatus == 0
      rescue Errno::ENOENT
        raise TmuxError, 'tmux is not installed or not in PATH'
      end

      def kill_session(session_name)
        _stdout, _stderr, status = execute_tmux_command('kill-session', '-t', session_name)
        status.exitstatus == 0
      rescue Errno::ENOENT
        raise TmuxError, 'tmux is not installed or not in PATH'
      end

      def session_exists?(session_name)
        _stdout, _stderr, status = execute_tmux_command('has-session', '-t', session_name)
        status.exitstatus == 0
      rescue Errno::ENOENT
        false
      end

      def list_sessions
        stdout, _stderr, status = execute_tmux_command('list-sessions')
        return [] unless status.exitstatus == 0

        parse_session_list(stdout)
      rescue Errno::ENOENT
        []
      end

      def send_keys(session_name, command)
        _stdout, _stderr, status = execute_tmux_command('send-keys', '-t', session_name, command, 'Enter')
        status.exitstatus == 0
      rescue Errno::ENOENT
        false
      end

      def capture_pane(session_name)
        stdout, _stderr, status = execute_tmux_command('capture-pane', '-t', session_name, '-p')
        return nil unless status.exitstatus == 0

        stdout
      rescue Errno::ENOENT
        nil
      end

      private

      def execute_tmux_command(*args)
        Open3.capture3('tmux', *args)
      end

      def parse_session_list(output)
        output.lines.map { |line| line.split(':').first }.compact
      end
    end
  end
end