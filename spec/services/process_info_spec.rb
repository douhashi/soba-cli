# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/soba/services/process_info'

RSpec.describe Soba::Services::ProcessInfo do
  let(:process_info) { described_class.new(pid) }
  let(:pid) { Process.pid }

  describe '#memory_usage_mb' do
    context 'when process exists' do
      it 'returns memory usage in megabytes' do
        memory_mb = process_info.memory_usage_mb
        expect(memory_mb).to be_a(Float)
        expect(memory_mb).to be > 0
      end
    end

    context 'when process does not exist' do
      let(:pid) { 999999 }

      it 'returns nil' do
        expect(process_info.memory_usage_mb).to be_nil
      end
    end

    context 'on Linux system' do
      before do
        allow(File).to receive(:exist?).with("/proc/#{pid}/status").and_return(true)
        allow(File).to receive(:read).with("/proc/#{pid}/status").and_return(
          <<~STATUS
            Name:	ruby
            Umask:	0002
            State:	S (sleeping)
            VmRSS:	  46336 kB
            VmSize:	 120000 kB
          STATUS
        )
      end

      it 'reads memory from /proc filesystem' do
        expect(process_info.memory_usage_mb).to be_within(0.1).of(45.25)
      end
    end

    context 'on macOS system' do
      before do
        allow(File).to receive(:exist?).with("/proc/#{pid}/status").and_return(false)
        # Mock the backtick method and the global $? variable
        allow(process_info).to receive(:`).with("ps -o rss= -p #{pid} 2>/dev/null") do
          # Set the global $? to a successful status
          `echo success > /dev/null`  # This sets $? to success
          "  46336\n"
        end
      end

      it 'uses ps command to get memory' do
        expect(process_info.memory_usage_mb).to be_within(0.1).of(45.25)
      end
    end
  end

  describe '#exists?' do
    context 'when process exists' do
      it 'returns true' do
        expect(process_info.exists?).to be true
      end
    end

    context 'when process does not exist' do
      let(:pid) { 999999 }

      it 'returns false' do
        expect(process_info.exists?).to be false
      end
    end
  end
end