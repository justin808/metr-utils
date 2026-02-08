# frozen_string_literal: true

module TogglDb
  # Metr-specific output formatting for productivity research templates.
  # Provides both strict Metr format and human-friendly default format.
  # rubocop:disable Metrics/ModuleLength
  module MetrFormatter
    # Constants for choice fields
    TASK_TYPES = %w[Feature Bug Refactor Tests Docs Investigation Review Meeting Other].freeze

    CONFIDENCE_OPTIONS = [
      'Very uncertain',
      'Somewhat confident',
      'Very confident'
    ].freeze

    WHY_AI_OPTIONS = [
      'Tedious/repetitive',
      'Outside my expertise',
      'Needs boilerplate',
      'Exploring/uncertain',
      'Time pressure',
      'Default workflow'
    ].freeze

    WOULD_DO_WITHOUT_AI_OPTIONS = [
      'Yes same scope',
      'Yes reduced scope',
      'Probably not',
      'Definitely not'
    ].freeze

    OUTCOMES = [
      'Completed',
      'Reduced scope',
      'Abandoned',
      'Still in progress'
    ].freeze

    QUALITY_RATINGS = [
      'Notably worse',
      'Slightly worse',
      'Same',
      'Slightly better',
      'Notably better'
    ].freeze

    AI_INVOLVED_OPTIONS = [
      'No',
      'Waiting',
      'Active',
      'Using output'
    ].freeze

    FOCUS_OPTIONS = [
      'Fully on one thing',
      'Switching',
      'Distracted'
    ].freeze

    AI_VANISHED_OPTIONS = [
      'Unaffected',
      'Slower',
      'Much longer',
      'Blocked'
    ].freeze

    YES_NO_DK_OPTIONS = ['Yes', 'No', "Don't know"].freeze

    module_function

    def format_task_start(task, format: :metr)
      case format.to_sym
      when :metr
        format_task_start_metr(task)
      else
        format_task_start_default(task)
      end
    end

    def format_task_end(data, format: :metr)
      case format.to_sym
      when :metr
        format_task_end_metr(data)
      else
        format_task_end_default(data)
      end
    end

    def format_snapshot(data, format: :metr)
      case format.to_sym
      when :metr
        format_snapshot_metr(data)
      else
        format_snapshot_default(data)
      end
    end

    # --- TASK START formatters ---

    # rubocop:disable Metrics/AbcSize
    def format_task_start_metr(task)
      lines = []
      lines << '=== TASK START ==='
      lines << "Task ID: #{task['id']}"
      lines << "Time: #{format_time(task['started_at'])}"
      lines << ''
      lines << "1. DESCRIPTION: #{task['description']}"
      lines << ''
      lines << "2. USING AI? #{task['use_ai'] ? 'Yes' : 'No'}"
      lines << ''
      lines << "3. EXPECTED TIME: #{task['expected_time_minutes']} min"
      lines << ''
      lines << "4. WITHOUT AI WOULD TAKE: #{task['without_ai_time_minutes']} min"
      lines << '   (If not using AI, same as #3)'
      lines << "   Confidence: #{task['confidence']}"
      lines << ''
      why_ai_label = task['use_ai'] ? '5. WHY AI?' : '5. WHY AI? (skip if no AI)'
      lines << why_ai_label
      format_checkbox_options(lines, WHY_AI_OPTIONS, task['why_ai'])
      lines << ''
      would_do_label = '6. WITHOUT AI, WOULD YOU DO THIS?'
      would_do_label += ' (skip if no AI)' unless task['use_ai']
      lines << would_do_label
      format_checkbox_options(lines, WOULD_DO_WITHOUT_AI_OPTIONS, task['would_do_without_ai'])
      lines << ''
      lines << "7. TYPE: #{task['type']}"
      lines.join("\n")
    end
    # rubocop:enable Metrics/AbcSize

    def format_task_start_default(task)
      lines = []
      lines << ('=' * 60)
      lines << 'TASK START'
      lines << "Task ID: #{task['id']}"
      lines << "Description: #{task['description']}"
      lines << "Started: #{format_time(task['started_at'])}"
      lines << "Type: #{task['type']}"
      lines << ''
      lines << "Will use AI: #{task['use_ai'] ? 'Yes' : 'No'}"
      lines << "Expected time: #{task['expected_time_minutes']} min"
      lines << "Without AI estimate: #{task['without_ai_time_minutes']} min"
      lines << "Confidence: #{task['confidence']}/5"
      lines << "Why AI: #{task['why_ai']}" if task['why_ai']
      lines << "Would do without AI: #{task['would_do_without_ai'] ? 'Yes' : 'No'}"
      lines << ('=' * 60)
      lines.join("\n")
    end

    # --- TASK END formatters ---

    # rubocop:disable Metrics/AbcSize
    def format_task_end_metr(data)
      lines = []
      lines << '=== TASK END ==='
      lines << "Task ID: #{data[:task_id] || '[unknown]'}"
      lines << "Time: #{format_time(data[:end_time])}"
      lines << ''
      lines << "1. USED AI? #{data[:used_ai] ? 'Yes' : 'No'}"
      lines << ''
      lines << "2. TOTAL ELAPSED: #{data[:total_elapsed_minutes]} min"
      lines << ''
      lines << '3. TIME BREAKDOWN:'
      lines << "   Active work: #{data[:active_work_minutes] || '___'} min"
      lines << "   Waiting/reviewing AI: #{data[:waiting_ai_minutes] || '___'} min (0 if no AI)"
      lines << ''
      lines << '4. OUTCOME:'
      format_checkbox_options(lines, OUTCOMES, data[:outcome])
      lines << ''
      lines << '5. IF USED AI:'
      lines << "   % from AI: #{data[:ai_percentage] || '___'}"
      lines << "   # of AI turns: #{data[:ai_turns] || '___'}"
      lines << ''
      lines << "6. WITHOUT AI WOULD TAKE: #{data[:without_ai_minutes] || '___'} min"
      lines << '   (If no AI, same as #2)'
      lines << ''
      lines << '7. IF USED AI - QUALITY vs yourself:'
      format_checkbox_options(lines, QUALITY_RATINGS, data[:quality_vs_self])
      lines << ''
      lines << "8. NOTES: #{data[:notes] || ''}"
      lines.join("\n")
    end
    # rubocop:enable Metrics/AbcSize

    def format_task_end_default(data)
      lines = []
      lines << ('=' * 60)
      lines << 'TASK END'
      lines << "Task: #{data[:task_name]}"
      lines << "Clock: #{data[:clock_range]}"
      lines << "Focused time: #{format_duration_human(data[:total_elapsed_minutes])}"
      lines << "AI %: #{data[:ai_percentage]}% (#{data[:ai_details]})"
      lines << "With-AI estimate: #{data[:with_ai_estimate]}" if data[:with_ai_estimate]
      lines << "Without-AI estimate: #{data[:without_ai_minutes] || '[YOU FILL IN]'}"
      lines << "Quality: #{data[:quality_vs_self] || '[1-5]'}"
      lines << "Notes: App breakdown - #{data[:app_breakdown_text]}" if data[:app_breakdown_text]
      lines << ('=' * 60)
      lines.join("\n")
    end

    # --- SNAPSHOT formatters ---

    def format_snapshot_metr(data)
      lines = []
      lines << '=== SNAPSHOT ==='
      lines << "Time: #{format_time(data[:time])}"
      lines << ''
      lines << "1. AI involved? #{data[:ai_involved] || '[No / Waiting / Active / Using output]'}"
      lines << "2. Focus: #{data[:focus] || '[Fully on one thing / Switching / Distracted]'}"
      lines << "3. Same task as last snapshot? #{data[:same_task] || '[Yes / No / Don\'t know]'}"
      lines << "4. If AI vanished: #{data[:ai_vanished_impact] || '[Unaffected / Slower / Much longer / Blocked]'}"
      lines << "5. What are you doing? #{data[:what] || '[description]'}"
      lines << "   Type: #{data[:type] || '[Code / Debug / Research / Write / Meet / Plan / Break / Other]'}"
      lines.join("\n")
    end

    def format_snapshot_default(data)
      lines = []
      lines << ('=' * 60)
      lines << 'SNAPSHOT'
      lines << "Time: #{format_time(data[:time])}"
      lines << ''
      lines << "What: #{data[:what]}"
      lines << "Type: #{data[:type]}"
      lines << "AI involved: #{data[:ai_involved]}"
      lines << "Focus: #{data[:focus]}"
      lines << "Same task: #{data[:same_task]}"
      lines << "If AI vanished: #{data[:ai_vanished_impact]}"
      lines << ('=' * 60)
      lines.join("\n")
    end

    # --- Helper methods ---

    def format_checkbox_options(lines, options, selected)
      selected_values = Array(selected)
      options.each do |opt|
        marker = selected_values.include?(opt) ? 'x' : ' '
        lines << "   [#{marker}] #{opt}"
      end
    end

    def format_time(time)
      return Time.now.strftime('%Y-%m-%d %H:%M') if time.nil?

      case time
      when String
        Time.parse(time).strftime('%Y-%m-%d %H:%M')
      when Time
        time.strftime('%Y-%m-%d %H:%M')
      else
        time.to_s
      end
    end

    def format_duration_human(minutes)
      return "#{minutes}min" if minutes < 60

      hours = minutes / 60.0
      format('%.1fhr', hours)
    end
  end
  # rubocop:enable Metrics/ModuleLength
end
