# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'open3'

RSpec.describe 'Tebako Binary Build Integration', :integration do
  let(:project_root) { File.expand_path('../..', File.dirname(__FILE__)) }
  let(:script_path) { File.join(project_root, 'scripts/build-tebako.sh') }
  let(:dist_dir) { File.join(project_root, 'dist') }
  let(:binary_path) { File.join(dist_dir, 'soba-linux-x64') }

  describe 'build script validation' do
    it 'validates the build environment' do
      stdout, stderr, status = Open3.capture3("#{script_path} --validate")

      if status.success?
        expect(stdout).to include('Validation completed successfully')
      else
        # Docker might not be running, which is acceptable in test environment
        # Check both stdout and stderr for Docker-related messages
        output = stdout + stderr
        expect(output).to include('Docker')
      end
    end

    it 'shows build configuration' do
      stdout, _stderr, status = Open3.capture3("#{script_path} --show-config")

      expect(status).to be_success
      expect(stdout).to include('RUBY_VERSION: 3.3.7')
      expect(stdout).to include('ENTRY_POINT: exe/soba')
      expect(stdout).to include('OUTPUT_DIR:')
    end

    it 'displays help information' do
      stdout, _stderr, status = Open3.capture3("#{script_path} --help")

      expect(status).to be_success
      expect(stdout).to include('Usage:')
      expect(stdout).to include('build-tebako.sh')
      expect(stdout).to include('Options:')
    end
  end

  describe 'Docker availability check' do
    before do
      # Skip this entire describe block if Docker is not installed
      unless system('which docker > /dev/null 2>&1')
        skip 'Docker is not installed, skipping Docker-related tests'
      end
    end

    it 'checks for Docker installation' do
      stdout, stderr, _status = Open3.capture3("#{script_path} --check-docker")
      output = stdout + stderr

      if system('docker info > /dev/null 2>&1')
        expect(output).to include('Docker is available')
      else
        expect(output).to include('Docker daemon is not running')
      end
    end
  end

  describe 'Rake task integration' do
    it 'can be invoked through Rake' do
      # Test that the Rake task exists and can be invoked (dry run)
      stdout, _stderr, status = Open3.capture3('rake -T build:tebako')

      expect(status).to be_success
      expect(stdout).to include('build:tebako')
      expect(stdout).to include('Build soba CLI as a standalone binary using Tebako')
    end
  end

  # NOTE: Actual build test is commented out as it requires Docker and takes significant time
  # Uncomment for full integration testing in CI/CD environment

  # describe 'binary build process', :slow do
  #   before do
  #     # Ensure Docker is running
  #     unless system('docker info > /dev/null 2>&1')
  #       skip 'Docker daemon is not running'
  #     end
  #   end
  #
  #   after do
  #     # Clean up build artifacts
  #     FileUtils.rm_rf(dist_dir) if Dir.exist?(dist_dir)
  #   end
  #
  #   it 'builds a functional binary' do
  #     # Run the build
  #     stdout, stderr, status = Open3.capture3(script_path)
  #
  #     expect(status).to be_success
  #     expect(File.exist?(binary_path)).to be true
  #
  #     # Test the binary
  #     if File.exist?(binary_path)
  #       version_output = `#{binary_path} --version 2>&1`
  #       expect(version_output).to include('soba')
  #     end
  #   end
  # end
end