# frozen_string_literal: true

require_relative 'metr_formatter'
require_relative '../task_store'

module TogglDb
  class CLI < Thor
    desc 'task-start', 'Start a new Metr tracked task'
    long_desc <<~DESC
      Generates a TASK START template and begins tracking a new task for Metr productivity research.

      Interactive prompts collect all required fields:
        - Task description
        - Whether AI will be used
        - Expected time with AI
        - Estimated time without AI
        - Confidence level (1-5)
        - Why using AI (if applicable)
        - Whether you would do this without AI
        - Task type (Code, Debug, Research, etc.)

      Examples:
        $ toggl_db task-start                      # Interactive mode
        $ toggl_db task-start --format metr       # Output in strict Metr format
        $ toggl_db task-start -o ~/tasks.txt      # Write output to file
    DESC
    option :id, type: :numeric, desc: 'Specify task ID (default: auto-increment)'
    option :format, aliases: '-f', type: :string, enum: %w[default metr], default: 'metr',
                    desc: 'Output format'
    option :output, aliases: '-o', type: :string, desc: 'Write output to file'
    def task_start
      task_data = prompt_task_start_data
      task = TaskStore.create_task(task_data)

      output = MetrFormatter.format_task_start(task, format: options[:format].to_sym)
      write_output(output)

      say ''
      say "Task ##{task['id']} started. Use 'toggl_db task-end' when complete.", :green
    end

    private

    def prompt_task_start_data
      say ''
      say 'Starting new task...', :green
      say ''

      description = ask('Task description:')
      use_ai = yes?('Will you use AI? (y/n)')
      expected_time = ask_numeric('Expected time with AI (minutes):')
      without_ai_time = ask_numeric('Without AI would take (minutes):')
      confidence = ask_confidence
      why_ai = use_ai ? ask('Why use AI for this task?') : nil
      would_do_without_ai = yes?('Would you do this task without AI? (y/n)')
      task_type = ask_choice('Task type:', MetrFormatter::TASK_TYPES)

      {
        description: description,
        type: task_type,
        use_ai: use_ai,
        expected_time_minutes: expected_time,
        without_ai_time_minutes: without_ai_time,
        confidence: confidence,
        why_ai: why_ai,
        would_do_without_ai: would_do_without_ai
      }
    end

    def ask_numeric(prompt, default: nil)
      default_hint = default ? " [#{default}]" : ''
      response = ask("#{prompt}#{default_hint}")
      return default if response.strip.empty? && default

      response.to_i
    end

    def ask_confidence
      say 'Confidence level (1-5):'
      say '  1 = Very uncertain'
      say '  3 = Moderate confidence'
      say '  5 = Very confident'
      response = ask('Select (1-5):')
      response.to_i.clamp(1, 5)
    end

    def ask_choice(prompt, choices, default: nil)
      say prompt
      choices.each_with_index { |c, i| say "  #{i + 1}. #{c}" }
      default_hint = default ? " [#{choices.index(default) + 1}]" : ''
      response = ask("Select (1-#{choices.length})#{default_hint}:")

      return default if response.strip.empty? && default

      idx = response.to_i - 1
      idx >= 0 && idx < choices.length ? choices[idx] : (default || choices.first)
    end

    def write_output(content)
      if options[:output]
        File.write(options[:output], "#{content}\n")
        say "Output written to: #{options[:output]}", :green
      else
        say ''
        say content
      end
    end
  end
end
