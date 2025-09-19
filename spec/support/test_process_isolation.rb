# frozen_string_literal: true

require 'soba/services/test_process_manager'

RSpec.configure do |config|
  config.before(:each) do |example|
    # Only enable test mode for tests explicitly marked with test_process_isolation
    if example.metadata[:test_process_isolation]
      # Set test mode environment variable
      ENV['SOBA_TEST_MODE'] = 'true'

      # Initialize test process manager and ensure test environment
      @test_process_manager = Soba::Services::TestProcessManager.new
      @test_id = @test_process_manager.generate_test_id

      result = @test_process_manager.ensure_test_environment
      unless result[:success]
        raise "Failed to setup test environment: #{result[:error]}"
      end

      # Store test ID for cleanup
      example.metadata[:test_id] = @test_id
    end
  end

  config.after(:each) do |example|
    if example.metadata[:test_process_isolation]
      test_id = example.metadata[:test_id]

      if test_id && @test_process_manager
        # Clean up test processes
        cleanup_result = @test_process_manager.cleanup_test_processes(test_id)

        unless cleanup_result[:success]
          warn "Warning: Failed to cleanup test processes for #{test_id}: #{cleanup_result[:error]}"
        end

        # Log cleaned processes for debugging if any
        if cleanup_result[:cleaned_processes]&.any?
          puts "Cleaned up test processes: #{cleanup_result[:cleaned_processes]}"
        end
      end

      # Clean up environment variable
      ENV.delete('SOBA_TEST_MODE')
    end
  end

  # Ensure test directory cleanup on exit
  config.after(:suite) do
    test_pid_dir = '/tmp/soba-test-pids'
    if Dir.exist?(test_pid_dir)
      begin
        # Clean up any remaining PID files
        Dir.glob("#{test_pid_dir}/*.pid").each do |pid_file|
          File.delete(pid_file) if File.exist?(pid_file)
        end

        # Remove directory if empty
        Dir.rmdir(test_pid_dir) if Dir.empty?(test_pid_dir)
      rescue StandardError => e
        warn "Warning: Failed to cleanup test directory #{test_pid_dir}: #{e.message}"
      end
    end
  end
end

# Helper methods available in tests
module TestProcessIsolationHelpers
  def current_test_id
    RSpec.current_example&.metadata&.[](:test_id)
  end

  def test_process_manager
    @test_process_manager
  end

  def in_test_mode?
    ENV['SOBA_TEST_MODE'] == 'true'
  end
end

RSpec.configure do |config|
  config.include TestProcessIsolationHelpers
end