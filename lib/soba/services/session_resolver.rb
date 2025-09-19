# frozen_string_literal: true

module Soba
  module Services
    class SessionResolver
      def initialize(pid_manager: nil, tmux_manager: nil)
        @pid_manager = pid_manager || PidManager.new
        @tmux_manager = tmux_manager || TmuxSessionManager.new
      end

      def resolve_active_session(repository)
        pid = @pid_manager.read
        return nil unless pid

        session_name = generate_session_name(repository, pid)

        if @tmux_manager.session_exists?(session_name)
          session_name
        else
          @pid_manager.delete
          nil
        end
      rescue Errno::ENOENT
        nil
      end

      def find_all_repository_sessions(repository)
        pid = @pid_manager.read
        return [] unless pid

        session_name = generate_session_name(repository, pid)
        active = @tmux_manager.session_exists?(session_name)

        unless active
          @pid_manager.delete
        end

        [{
          name: session_name,
          pid: pid,
          active: active
        }]
      end

      def generate_session_name(repository, pid)
        raise ArgumentError, "PID cannot be nil" if pid.nil?

        sanitized_repo = repository.to_s.gsub(/[^a-zA-Z0-9-]/, "-")
        "soba-#{sanitized_repo}-#{pid}"
      end

      def cleanup_stale_sessions(repository)
        pid = @pid_manager.read
        return [] unless pid

        session_name = generate_session_name(repository, pid)
        unless @tmux_manager.session_exists?(session_name)
          @pid_manager.delete
          [pid]
        else
          []
        end
      end

      private

      attr_reader :pid_manager, :tmux_manager
    end
  end
end