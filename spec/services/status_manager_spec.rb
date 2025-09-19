# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'json'
require_relative '../../lib/soba/services/status_manager'

RSpec.describe Soba::Services::StatusManager do
  let(:temp_file) { Tempfile.new(['status', '.json']) }
  let(:status_manager) { described_class.new(temp_file.path) }

  after do
    temp_file.unlink
  end

  describe '#write' do
    it 'writes status data to file' do
      status_data = {
        current_issue: { number: 92, phase: 'soba:doing' },
        last_processed: { number: 91, completed_at: Time.now.iso8601 },
        memory_mb: 45.2,
      }

      status_manager.write(status_data)

      file_content = JSON.parse(File.read(temp_file.path))
      expect(file_content['current_issue']['number']).to eq(92)
      expect(file_content['last_processed']['number']).to eq(91)
      expect(file_content['memory_mb']).to eq(45.2)
    end

    it 'creates file if it does not exist' do
      FileUtils.rm_f(temp_file.path)
      expect(File.exist?(temp_file.path)).to be false

      status_manager.write({ test: 'data' })
      expect(File.exist?(temp_file.path)).to be true
    end

    it 'atomically updates file' do
      # Write initial data
      status_manager.write({ version: 1 })

      # Simulate concurrent read while writing
      thread = Thread.new do
        10.times do
          content = status_manager.read
          expect(content).to be_a(Hash) if content
        end
      end

      # Update data multiple times
      5.times do |i|
        status_manager.write({ version: i + 2 })
      end

      thread.join
    end
  end

  describe '#read' do
    context 'when file exists with valid JSON' do
      before do
        File.write(temp_file.path, JSON.pretty_generate({
          current_issue: { number: 92 },
          memory_mb: 32.5,
        }))
      end

      it 'returns parsed JSON data' do
        data = status_manager.read
        expect(data).to be_a(Hash)
        expect(data[:current_issue][:number]).to eq(92)
        expect(data[:memory_mb]).to eq(32.5)
      end
    end

    context 'when file does not exist' do
      before do
        FileUtils.rm_f(temp_file.path)
      end

      it 'returns nil' do
        expect(status_manager.read).to be_nil
      end
    end

    context 'when file contains invalid JSON' do
      before do
        File.write(temp_file.path, "invalid json{")
      end

      it 'returns nil and does not raise error' do
        expect(status_manager.read).to be_nil
      end
    end

    context 'when file is empty' do
      before do
        FileUtils.touch(temp_file.path)
      end

      it 'returns nil' do
        expect(status_manager.read).to be_nil
      end
    end
  end

  describe '#update_current_issue' do
    it 'updates only the current Issue information' do
      initial_data = {
        current_issue: { number: 91, phase: 'soba:planning' },
        last_processed: { number: 90 },
        memory_mb: 30.0,
      }
      status_manager.write(initial_data)

      status_manager.update_current_issue(92, 'soba:doing')

      data = status_manager.read
      expect(data[:current_issue][:number]).to eq(92)
      expect(data[:current_issue][:phase]).to eq('soba:doing')
      expect(data[:current_issue]).to have_key(:started_at)
      expect(data[:last_processed][:number]).to eq(90) # Should not change
      expect(data[:memory_mb]).to eq(30.0) # Should not change
    end

    it 'creates new status file if it does not exist' do
      FileUtils.rm_f(temp_file.path)

      status_manager.update_current_issue(92, 'soba:doing')

      data = status_manager.read
      expect(data[:current_issue][:number]).to eq(92)
    end
  end

  describe '#update_last_processed' do
    it 'moves current Issue to last processed' do
      initial_data = {
        current_issue: { number: 92, phase: 'soba:doing', started_at: Time.now.iso8601 },
        memory_mb: 30.0,
      }
      status_manager.write(initial_data)

      status_manager.update_last_processed

      data = status_manager.read
      expect(data[:current_issue]).to be_nil
      expect(data[:last_processed][:number]).to eq(92)
      expect(data[:last_processed]).to have_key(:completed_at)
    end
  end

  describe '#update_memory' do
    it 'updates only memory information' do
      initial_data = {
        current_issue: { number: 92 },
        memory_mb: 30.0,
      }
      status_manager.write(initial_data)

      status_manager.update_memory(45.5)

      data = status_manager.read
      expect(data[:memory_mb]).to eq(45.5)
      expect(data[:current_issue][:number]).to eq(92) # Should not change
    end
  end

  describe '#clear' do
    it 'removes the status file' do
      status_manager.write({ test: 'data' })
      expect(File.exist?(temp_file.path)).to be true

      status_manager.clear

      expect(File.exist?(temp_file.path)).to be false
    end
  end
end