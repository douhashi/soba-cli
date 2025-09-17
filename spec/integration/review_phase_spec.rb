# frozen_string_literal: true

require 'spec_helper'
require 'soba/domain/phase_strategy'
require 'soba/configuration'
require 'tmpdir'

RSpec.describe 'Review Phase Integration' do
  let(:phase_strategy) { Soba::Domain::PhaseStrategy.new }

  describe 'review phase workflow' do
    context 'when issue has soba:review-requested label' do
      let(:labels) { ['soba:review-requested', 'feature'] }

      it 'determines review phase correctly' do
        phase = phase_strategy.determine_phase(labels)

        expect(phase).to eq(:review)
      end

      it 'returns correct next label for transition' do
        next_label = phase_strategy.next_label(:review)

        expect(next_label).to eq('soba:reviewing')
      end

      it 'returns correct current label for phase' do
        current_label = phase_strategy.current_label_for_phase(:review)

        expect(current_label).to eq('soba:review-requested')
      end

      it 'validates transition from review-requested to reviewing' do
        valid = phase_strategy.validate_transition('soba:review-requested', 'soba:reviewing')

        expect(valid).to be true
      end
    end

    context 'when issue has soba:reviewing label' do
      let(:labels) { ['soba:reviewing'] }

      it 'returns nil for phase (already in progress)' do
        phase = phase_strategy.determine_phase(labels)

        expect(phase).to be_nil
      end
    end

    context 'with configuration' do
      let(:temp_dir) { Dir.mktmpdir }
      let(:config_file) { File.join(temp_dir, '.soba', 'config.yml') }

      before do
        FileUtils.mkdir_p(File.dirname(config_file))
        File.write(config_file, <<~YAML)
          github:
            token: test_token
            repository: owner/repo
          workflow:
            interval: 20
          phase:
            review:
              command: claude
              options:
                - --dangerously-skip-permissions
              parameter: '/soba:review {{issue-number}}'
        YAML
      end

      after do
        FileUtils.rm_rf(temp_dir)
        Soba::Configuration.reset_config
      end

      it 'loads review phase configuration correctly' do
        config = Soba::Configuration.load!(path: config_file)

        expect(config.phase.review.command).to eq('claude')
        expect(config.phase.review.options).to eq(['--dangerously-skip-permissions'])
        expect(config.phase.review.parameter).to eq('/soba:review {{issue-number}}')
      end
    end
  end

  describe 'full workflow integration' do
    let(:issue_labels) do
      {
        todo: ['soba:todo'],
        planning: ['soba:planning'],
        ready: ['soba:ready'],
        doing: ['soba:doing'],
        review_requested: ['soba:review-requested'],
        reviewing: ['soba:reviewing'],
      }
    end

    it 'follows the complete phase transition flow' do
      # Plan phase
      expect(phase_strategy.determine_phase(issue_labels[:todo])).to eq(:plan)
      expect(phase_strategy.next_label(:plan)).to eq('soba:planning')

      # Implement phase
      expect(phase_strategy.determine_phase(issue_labels[:ready])).to eq(:implement)
      expect(phase_strategy.next_label(:implement)).to eq('soba:doing')

      # Review phase
      expect(phase_strategy.determine_phase(issue_labels[:review_requested])).to eq(:review)
      expect(phase_strategy.next_label(:review)).to eq('soba:reviewing')

      # In progress states return nil
      expect(phase_strategy.determine_phase(issue_labels[:planning])).to be_nil
      expect(phase_strategy.determine_phase(issue_labels[:doing])).to be_nil
      expect(phase_strategy.determine_phase(issue_labels[:reviewing])).to be_nil
    end

    it 'validates all phase transitions' do
      transitions = [
        ['soba:todo', 'soba:planning'],
        ['soba:planning', 'soba:ready'],
        ['soba:ready', 'soba:doing'],
        ['soba:doing', 'soba:review-requested'],
        ['soba:review-requested', 'soba:reviewing'],
      ]

      transitions.each do |from, to|
        expect(phase_strategy.validate_transition(from, to)).to be true
      end
    end

    it 'rejects invalid transitions' do
      invalid_transitions = [
        ['soba:todo', 'soba:doing'],
        ['soba:ready', 'soba:todo'],
        ['soba:review-requested', 'soba:ready'],
        ['soba:reviewing', 'soba:planning'],
      ]

      invalid_transitions.each do |from, to|
        expect(phase_strategy.validate_transition(from, to)).to be false
      end
    end
  end
end