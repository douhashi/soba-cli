# frozen_string_literal: true

require 'spec_helper'
require 'soba/services/workflow_executor'

RSpec.describe Soba::Services::WorkflowExecutor do
  let(:executor) { described_class.new }

  describe '#execute' do
    let(:phase_config) do
      double(
        command: 'echo',
        options: ['--test'],
        parameter: 'Issue {{issue-number}}'
      )
    end

    context 'when phase configuration exists' do
      it 'executes the command with proper arguments' do
        expect(Open3).to receive(:popen3).with('echo', '--test', 'Issue 123') do |&block|
          stdin = double('stdin', close: nil)
          stdout = double('stdout', read: 'Command output')
          stderr = double('stderr', read: '')
          thread = double('thread', value: double(exitstatus: 0))
          block.call(stdin, stdout, stderr, thread)
        end

        result = executor.execute(phase: phase_config, issue_number: 123)

        expect(result).to include(
          success: true,
          output: 'Command output',
          error: '',
          exit_code: 0
        )
      end

      it 'replaces {{issue-number}} placeholder with actual issue number' do
        expect(Open3).to receive(:popen3).with('echo', '--test', 'Issue 456') do |&block|
          stdin = double('stdin', close: nil)
          stdout = double('stdout', read: 'Issue 456')
          stderr = double('stderr', read: '')
          thread = double('thread', value: double(exitstatus: 0))
          block.call(stdin, stdout, stderr, thread)
        end

        result = executor.execute(phase: phase_config, issue_number: 456)

        expect(result[:output]).to eq('Issue 456')
      end

      it 'handles command failure' do
        expect(Open3).to receive(:popen3).with('echo', '--test', 'Issue 789') do |&block|
          stdin = double('stdin', close: nil)
          stdout = double('stdout', read: '')
          stderr = double('stderr', read: 'Command failed')
          thread = double('thread', value: double(exitstatus: 1))
          block.call(stdin, stdout, stderr, thread)
        end

        result = executor.execute(phase: phase_config, issue_number: 789)

        expect(result).to include(
          success: false,
          output: '',
          error: 'Command failed',
          exit_code: 1
        )
      end

      context 'when options are empty' do
        let(:phase_config) do
          double(
            command: 'echo',
            options: [],
            parameter: 'Hello {{issue-number}}'
          )
        end

        it 'executes command without options' do
          expect(Open3).to receive(:popen3).with('echo', 'Hello 100') do |&block|
            stdin = double('stdin', close: nil)
            stdout = double('stdout', read: 'Hello 100')
            stderr = double('stderr', read: '')
            thread = double('thread', value: double(exitstatus: 0))
            block.call(stdin, stdout, stderr, thread)
          end

          result = executor.execute(phase: phase_config, issue_number: 100)

          expect(result[:success]).to be true
        end
      end
    end

    context 'when phase configuration is nil' do
      let(:phase_config) { double(command: nil, options: nil, parameter: nil) }

      it 'returns nil' do
        result = executor.execute(phase: phase_config, issue_number: 123)

        expect(result).to be_nil
      end
    end

    context 'when command execution raises an error' do
      let(:phase_config) do
        double(
          command: 'nonexistent_command',
          options: [],
          parameter: 'test'
        )
      end

      it 'handles the exception gracefully' do
        expect(Open3).to receive(:popen3).and_raise(Errno::ENOENT.new('No such file or directory'))

        expect do
          executor.execute(phase: phase_config, issue_number: 123)
        end.to raise_error(Soba::Services::WorkflowExecutionError, /Failed to execute workflow command/)
      end
    end
  end

  describe '#build_command' do
    let(:phase_config) do
      double(
        command: 'claude',
        options: ['--dangerous', '--skip-check'],
        parameter: '/osoba:plan {{issue-number}}'
      )
    end

    it 'builds command array correctly' do
      command = executor.send(:build_command, phase_config, 42)

      expect(command).to eq(['claude', '--dangerous', '--skip-check', '/osoba:plan 42'])
    end

    it 'handles nil parameter' do
      config = double(command: 'ls', options: ['-la'], parameter: nil)

      command = executor.send(:build_command, config, 123)

      expect(command).to eq(['ls', '-la'])
    end

    it 'handles multiple placeholders' do
      config = double(
        command: 'echo',
        options: [],
        parameter: 'Issue {{issue-number}} - Number: {{issue-number}}'
      )

      command = executor.send(:build_command, config, 999)

      expect(command).to eq(['echo', 'Issue 999 - Number: 999'])
    end
  end
end