# frozen_string_literal: true

require 'open3'
require_relative 'errors'

module Soba
  module Infrastructure
    class TmuxClient
      def create_session(session_name)
        _stdout, _stderr, status = execute_tmux_command('new-session', '-d', '-s', session_name)
        status.exitstatus == 0
      rescue Errno::ENOENT
        raise TmuxNotInstalled, 'tmux is not installed or not in PATH'
      end

      def kill_session(session_name)
        _stdout, _stderr, status = execute_tmux_command('kill-session', '-t', session_name)
        status.exitstatus == 0
      rescue Errno::ENOENT
        raise TmuxNotInstalled, 'tmux is not installed or not in PATH'
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

      def create_window(session_name, window_name)
        _stdout, _stderr, status = execute_tmux_command('new-window', '-t', session_name, '-n', window_name)
        status.exitstatus == 0
      rescue Errno::ENOENT
        false
      end

      def switch_window(session_name, window_name)
        _stdout, _stderr, status = execute_tmux_command('select-window', '-t', "#{session_name}:#{window_name}")
        status.exitstatus == 0
      rescue Errno::ENOENT
        false
      end

      def list_windows(session_name)
        stdout, _stderr, status = execute_tmux_command('list-windows', '-t', session_name)
        return [] unless status.exitstatus == 0

        parse_window_list(stdout)
      rescue Errno::ENOENT
        []
      end

      def rename_window(session_name, old_name, new_name)
        _stdout, _stderr, status = execute_tmux_command('rename-window', '-t', "#{session_name}:#{old_name}", new_name)
        status.exitstatus == 0
      rescue Errno::ENOENT
        false
      end

      def split_pane(session_name, direction)
        flag = direction == :horizontal ? '-h' : '-v'
        _stdout, _stderr, status = execute_tmux_command('split-window', '-t', session_name, flag)
        status.exitstatus == 0
      rescue Errno::ENOENT
        false
      end

      def select_pane(session_name, pane_index)
        _stdout, _stderr, status = execute_tmux_command('select-pane', '-t', "#{session_name}.#{pane_index}")
        status.exitstatus == 0
      rescue Errno::ENOENT
        false
      end

      def resize_pane(session_name, direction, size)
        direction_flags = { up: '-U', down: '-D', left: '-L', right: '-R' }
        flag = direction_flags[direction]
        _stdout, _stderr, status = execute_tmux_command('resize-pane', '-t', session_name, flag, size.to_s)
        status.exitstatus == 0
      rescue Errno::ENOENT
        false
      end

      def close_pane(session_name, pane_index)
        _stdout, _stderr, status = execute_tmux_command('kill-pane', '-t', "#{session_name}.#{pane_index}")
        status.exitstatus == 0
      rescue Errno::ENOENT
        false
      end

      def session_info(session_name)
        format_string = '#{session_name}: #{session_windows} windows ' \
                        '(created #{session_created_string}) [#{session_width}x#{session_height}]'
        stdout, _stderr, status = execute_tmux_command('list-sessions', '-F', format_string)
        return nil unless status.exitstatus == 0

        parse_session_info(stdout, session_name)
      rescue Errno::ENOENT
        nil
      end

      def active_session
        stdout, _stderr, status = execute_tmux_command('display-message', '-p', '#{session_name}')
        return nil unless status.exitstatus == 0

        stdout.strip
      rescue Errno::ENOENT
        nil
      end

      def session_attached?(session_name)
        stdout, _stderr, status = execute_tmux_command('list-sessions', '-F', '#{session_name}: #{session_attached}',
'-f', "#{session_name}==#{session_name}")
        return false unless status.exitstatus == 0

        parse_attached_status(stdout)
      rescue Errno::ENOENT
        false
      end

      def find_pane(session_name)
        stdout, _stderr, status = execute_tmux_command('list-panes', '-t', session_name, '-F', '#{pane_id}')
        return nil unless status.exitstatus == 0

        # Return first pane ID
        stdout.lines.first&.strip
      rescue Errno::ENOENT
        nil
      end

      def capture_pane_continuous(pane_id)
        last_content = ""

        loop do
          stdout, _stderr, status = execute_tmux_command('capture-pane', '-t', pane_id, '-p', '-S', '-')
          break unless status.exitstatus == 0

          # Yield only new content
          if stdout != last_content
            new_lines = stdout[last_content.length..-1] || ""
            yield new_lines unless new_lines.empty?
            last_content = stdout
          end

          sleep 1
        end
      rescue Errno::ENOENT
        nil
      end

      def list_soba_sessions
        sessions = list_sessions
        sessions.select { |s| s.start_with?('soba-') }
      end

      def window_exists?(session_name, window_name)
        windows = list_windows(session_name)
        windows.include?(window_name)
      rescue Errno::ENOENT
        false
      end

      def split_window(session_name:, window_name:, vertical: true)
        flag = vertical ? '-v' : '-h'
        target = "#{session_name}:#{window_name}"
        stdout, _stderr, status = execute_tmux_command(
          'split-window', '-t', target, flag, '-P', '-F', '#{pane_id}'
        )
        return nil unless status.exitstatus == 0

        stdout.strip
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

      def parse_window_list(output)
        output.lines.map do |line|
          match = line.match(/^\d+:\s+([^\*\s]+)/)
          match[1] if match
        end.compact
      end

      def parse_session_info(output, session_name)
        output.lines.each do |line|
          if line.start_with?("#{session_name}:")
            # Handle both single line and multi-line formats
            combined_line = output.strip.gsub("\n", " ")
            match = combined_line.match(/^(.+?):\s+(\d+)\s+windows?\s+\(created\s+(.+?)\)\s*\[(\d+)x(\d+)\]/)
            if match
              return {
                name: match[1],
                windows: match[2].to_i,
                created_at: match[3],
                size: [match[4].to_i, match[5].to_i],
              }
            end
          end
        end
        nil
      end

      def parse_attached_status(output)
        return false if output.empty?

        line = output.lines.first.strip
        match = line.match(/:\s+(\d+)$/)
        return false unless match

        match[1] == '1'
      end
    end
  end
end