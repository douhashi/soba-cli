# frozen_string_literal: true

module Soba
  module Domain
    class PhaseStrategy
      PHASE_TRANSITIONS = {
        'soba:todo' => 'soba:queued',
        'soba:queued' => 'soba:planning',
        'soba:planning' => 'soba:ready',
        'soba:ready' => 'soba:doing',
        'soba:doing' => 'soba:review-requested',
        'soba:review-requested' => 'soba:reviewing',
        'soba:reviewing' => 'soba:requires-changes',
        'soba:requires-changes' => 'soba:revising',
        'soba:revising' => 'soba:review-requested',
      }.freeze

      PHASE_MAPPINGS = {
        plan: { current: 'soba:todo', next: 'soba:planning' },
        queued_to_planning: { current: 'soba:queued', next: 'soba:planning' },
        implement: { current: 'soba:ready', next: 'soba:doing' },
        review: { current: 'soba:review-requested', next: 'soba:reviewing' },
        revise: { current: 'soba:requires-changes', next: 'soba:revising' },
      }.freeze

      IN_PROGRESS_LABELS = %w(soba:planning soba:doing soba:reviewing soba:revising).freeze

      def determine_phase(labels)
        return nil if labels.blank?

        labels = labels.map(&:to_s)

        return nil if (labels & IN_PROGRESS_LABELS).any?

        return :plan if labels.include?('soba:todo')
        return :queued_to_planning if labels.include?('soba:queued')
        return :implement if labels.include?('soba:ready')
        return :review if labels.include?('soba:review-requested')
        return :revise if labels.include?('soba:requires-changes')

        nil
      end

      def next_label(phase)
        return nil unless phase

        PHASE_MAPPINGS.dig(phase, :next)
      end

      def current_label_for_phase(phase)
        return nil unless phase

        PHASE_MAPPINGS.dig(phase, :current)
      end

      def validate_transition(from_label, to_label)
        if from_label.nil? || to_label.nil?
          return false
        end

        if !from_label.start_with?('soba:') || !to_label.start_with?('soba:')
          return false
        end

        # Allow direct transition from soba:todo to soba:planning (legacy path)
        if from_label == 'soba:todo' && to_label == 'soba:planning'
          return true
        end

        PHASE_TRANSITIONS[from_label] == to_label
      end
    end
  end
end