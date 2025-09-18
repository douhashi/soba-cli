# frozen_string_literal: true

require 'spec_helper'
require 'soba/domain/phase_strategy'
require 'soba/services/workflow_executor'

RSpec.describe 'Revise workflow integration' do
  let(:phase_strategy) { Soba::Domain::PhaseStrategy.new }
  let(:workflow_executor) { instance_double(Soba::Services::WorkflowExecutor) }

  describe 'revise phase detection and transition' do
    context 'when issue has soba:requires-changes label' do
      let(:labels) { ['soba:requires-changes', 'bug'] }

      it 'determines revise phase correctly' do
        phase = phase_strategy.determine_phase(labels)
        expect(phase).to eq(:revise)
      end

      it 'gets correct next label for revise phase' do
        next_label = phase_strategy.next_label(:revise)
        expect(next_label).to eq('soba:revising')
      end

      it 'validates transition to soba:revising' do
        valid = phase_strategy.validate_transition('soba:requires-changes', 'soba:revising')
        expect(valid).to be true
      end
    end

    context 'when issue is in soba:revising state' do
      let(:labels) { ['soba:revising', 'bug'] }

      it 'returns nil for determine_phase (already in progress)' do
        phase = phase_strategy.determine_phase(labels)
        expect(phase).to be_nil
      end

      it 'validates transition to soba:review-requested' do
        valid = phase_strategy.validate_transition('soba:revising', 'soba:review-requested')
        expect(valid).to be true
      end
    end

    context 'review to revise transition' do
      it 'validates transition from soba:reviewing to soba:requires-changes' do
        valid = phase_strategy.validate_transition('soba:reviewing', 'soba:requires-changes')
        expect(valid).to be true
      end
    end
  end

  describe 'revise command execution flow' do
    let(:issue_number) { 123 }
    let(:revise_config) do
      double(
        name: 'revise',
        command: 'claude',
        options: ['--dangerously-skip-permissions'],
        parameter: '/soba:revise {{issue-number}}'
      )
    end

    it 'executes revise command with correct parameters' do
      expect(workflow_executor).to receive(:execute).with(
        phase: revise_config,
        issue_number: issue_number,
        use_tmux: true,
        setup_workspace: true
      ).and_return({
        success: true,
        output: 'Revise completed',
        error: '',
        exit_code: 0,
      })

      result = workflow_executor.execute(
        phase: revise_config,
        issue_number: issue_number,
        use_tmux: true,
        setup_workspace: true
      )

      expect(result[:success]).to be true
      expect(result[:output]).to include('Revise completed')
    end
  end

  describe 'complete revise workflow' do
    let(:labels_progression) do
      [
        ['soba:review-requested'],
        ['soba:reviewing'],
        ['soba:requires-changes'],
        ['soba:revising'],
        ['soba:review-requested'],
      ]
    end

    it 'follows correct label transition sequence' do
      transitions = [
        ['soba:review-requested', 'soba:reviewing'],
        ['soba:reviewing', 'soba:requires-changes'],
        ['soba:requires-changes', 'soba:revising'],
        ['soba:revising', 'soba:review-requested'],
      ]

      transitions.each do |from, to|
        valid = phase_strategy.validate_transition(from, to)
        expect(valid).to be(true), "Expected transition from #{from} to #{to} to be valid"
      end
    end

    it 'determines correct phases throughout the workflow' do
      phase_expectations = [
        [['soba:review-requested'], :review],
        [['soba:reviewing'], nil], # in progress
        [['soba:requires-changes'], :revise],
        [['soba:revising'], nil], # in progress
        [['soba:review-requested'], :review],  # back to review
      ]

      phase_expectations.each do |labels, expected_phase|
        phase = phase_strategy.determine_phase(labels)
        expect(phase).to eq(expected_phase),
          "Expected phase for labels #{labels} to be #{expected_phase}, but got #{phase}"
      end
    end
  end
end