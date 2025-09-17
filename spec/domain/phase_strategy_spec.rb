# frozen_string_literal: true

require 'spec_helper'
require 'soba/domain/phase_strategy'

RSpec.describe Soba::Domain::PhaseStrategy do
  let(:strategy) { described_class.new }

  describe '#determine_phase' do
    context 'when issue has soba:todo label' do
      let(:labels) { ['bug', 'soba:todo', 'enhancement'] }

      it 'returns :plan phase' do
        phase = strategy.determine_phase(labels)

        expect(phase).to eq(:plan)
      end
    end

    context 'when issue has soba:ready label' do
      let(:labels) { ['soba:ready', 'feature'] }

      it 'returns :implement phase' do
        phase = strategy.determine_phase(labels)

        expect(phase).to eq(:implement)
      end
    end

    context 'when issue has soba:review-requested label' do
      let(:labels) { ['soba:review-requested', 'feature'] }

      it 'returns :review phase' do
        phase = strategy.determine_phase(labels)

        expect(phase).to eq(:review)
      end
    end

    context 'when issue has soba:queued label' do
      let(:labels) { ['soba:queued'] }

      it 'returns :queued_to_planning phase' do
        phase = strategy.determine_phase(labels)

        expect(phase).to eq(:queued_to_planning)
      end
    end

    context 'when issue has soba:planning label' do
      let(:labels) { ['soba:planning'] }

      it 'returns nil (already in progress)' do
        phase = strategy.determine_phase(labels)

        expect(phase).to be_nil
      end
    end

    context 'when issue has soba:doing label' do
      let(:labels) { ['soba:doing', 'priority'] }

      it 'returns nil (already in progress)' do
        phase = strategy.determine_phase(labels)

        expect(phase).to be_nil
      end
    end

    context 'when issue has soba:reviewing label' do
      let(:labels) { ['soba:reviewing'] }

      it 'returns nil (already in progress)' do
        phase = strategy.determine_phase(labels)

        expect(phase).to be_nil
      end
    end

    context 'when issue has no soba labels' do
      let(:labels) { ['bug', 'enhancement'] }

      it 'returns nil' do
        phase = strategy.determine_phase(labels)

        expect(phase).to be_nil
      end
    end

    context 'when labels is empty' do
      let(:labels) { [] }

      it 'returns nil' do
        phase = strategy.determine_phase(labels)

        expect(phase).to be_nil
      end
    end

    context 'when labels is nil' do
      let(:labels) { nil }

      it 'returns nil' do
        phase = strategy.determine_phase(labels)

        expect(phase).to be_nil
      end
    end
  end

  describe '#next_label' do
    context 'for plan phase' do
      it 'returns soba:planning' do
        label = strategy.next_label(:plan)

        expect(label).to eq('soba:planning')
      end
    end

    context 'for implement phase' do
      it 'returns soba:doing' do
        label = strategy.next_label(:implement)

        expect(label).to eq('soba:doing')
      end
    end

    context 'for review phase' do
      it 'returns soba:reviewing' do
        label = strategy.next_label(:review)

        expect(label).to eq('soba:reviewing')
      end
    end

    context 'for queued_to_planning phase' do
      it 'returns soba:planning' do
        label = strategy.next_label(:queued_to_planning)

        expect(label).to eq('soba:planning')
      end
    end

    context 'for unknown phase' do
      it 'returns nil' do
        label = strategy.next_label(:unknown)

        expect(label).to be_nil
      end
    end

    context 'for nil phase' do
      it 'returns nil' do
        label = strategy.next_label(nil)

        expect(label).to be_nil
      end
    end
  end

  describe '#validate_transition' do
    context 'from soba:todo to soba:queued' do
      it 'returns true' do
        result = strategy.validate_transition('soba:todo', 'soba:queued')

        expect(result).to be true
      end
    end

    context 'from soba:queued to soba:planning' do
      it 'returns true' do
        result = strategy.validate_transition('soba:queued', 'soba:planning')

        expect(result).to be true
      end
    end

    context 'from soba:todo to soba:planning' do
      it 'returns true' do
        result = strategy.validate_transition('soba:todo', 'soba:planning')

        expect(result).to be true
      end
    end

    context 'from soba:ready to soba:doing' do
      it 'returns true' do
        result = strategy.validate_transition('soba:ready', 'soba:doing')

        expect(result).to be true
      end
    end

    context 'from soba:planning to soba:ready' do
      it 'returns true' do
        result = strategy.validate_transition('soba:planning', 'soba:ready')

        expect(result).to be true
      end
    end

    context 'from soba:doing to soba:review-requested' do
      it 'returns true' do
        result = strategy.validate_transition('soba:doing', 'soba:review-requested')

        expect(result).to be true
      end
    end

    context 'from soba:review-requested to soba:reviewing' do
      it 'returns true' do
        result = strategy.validate_transition('soba:review-requested', 'soba:reviewing')

        expect(result).to be true
      end
    end

    context 'from soba:todo directly to soba:doing' do
      it 'returns false (invalid transition)' do
        result = strategy.validate_transition('soba:todo', 'soba:doing')

        expect(result).to be false
      end
    end

    context 'from soba:ready back to soba:todo' do
      it 'returns false (backward transition)' do
        result = strategy.validate_transition('soba:ready', 'soba:todo')

        expect(result).to be false
      end
    end

    context 'with non-soba labels' do
      it 'returns false' do
        result = strategy.validate_transition('bug', 'enhancement')

        expect(result).to be false
      end
    end

    context 'with nil values' do
      it 'returns false' do
        expect(strategy.validate_transition(nil, 'soba:planning')).to be false
        expect(strategy.validate_transition('soba:todo', nil)).to be false
        expect(strategy.validate_transition(nil, nil)).to be false
      end
    end
  end

  describe '#current_label_for_phase' do
    context 'for plan phase' do
      it 'returns soba:todo' do
        label = strategy.current_label_for_phase(:plan)

        expect(label).to eq('soba:todo')
      end
    end

    context 'for implement phase' do
      it 'returns soba:ready' do
        label = strategy.current_label_for_phase(:implement)

        expect(label).to eq('soba:ready')
      end
    end

    context 'for review phase' do
      it 'returns soba:review-requested' do
        label = strategy.current_label_for_phase(:review)

        expect(label).to eq('soba:review-requested')
      end
    end

    context 'for queued_to_planning phase' do
      it 'returns soba:queued' do
        label = strategy.current_label_for_phase(:queued_to_planning)

        expect(label).to eq('soba:queued')
      end
    end

    context 'for unknown phase' do
      it 'returns nil' do
        label = strategy.current_label_for_phase(:unknown)

        expect(label).to be_nil
      end
    end
  end
end