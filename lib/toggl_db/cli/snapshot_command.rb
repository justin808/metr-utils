# frozen_string_literal: true

require_relative 'metr_formatter'
require_relative '../task_store'

module TogglDb
  class CLI < Thor
    desc 'snapshot', 'Record a Metr productivity snapshot'
    long_desc <<~DESC
      Records a point-in-time snapshot of current work status for Metr productivity research.

      Prompts for:
        - AI involvement (No, Waiting, Active, Using output)
        - Focus level (Fully on one thing, Switching, Distracted)
        - Same task as last snapshot (Yes, No, Don't know)
        - Impact if AI vanished (Unaffected, Slower, Much longer, Blocked)
        - What you're doing (one line description)
        - Task type (Code, Debug, Research, Write, Meet, Plan, Break, Other)

      Examples:
        $ toggl_db snapshot                       # Interactive snapshot
        $ toggl_db snapshot --format metr        # Strict Metr format
        $ toggl_db snapshot -o ~/snapshots.txt   # Append to file
        $ toggl_db snapshot --task-id 3          # Link to task #3
    DESC
    option :format, aliases: '-f', type: :string, enum: %w[default metr], default: 'metr',
                    desc: 'Output format'
    option :output, aliases: '-o', type: :string, desc: 'Write output to file'
    option :task_id, type: :numeric, desc: 'Link snapshot to a specific task ID'
    option :append, aliases: '-a', type: :boolean, default: false,
                    desc: 'Append to output file instead of overwriting'
    def snapshot
      snapshot_data = prompt_snapshot_data
      task_id = options[:task_id] || TaskStore.current_task&.dig('id')

      # Save to task store if we have a task
      if task_id
        TaskStore.add_snapshot(task_id, snapshot_data)
        say "Snapshot added to task ##{task_id}", :cyan
      end

      output = MetrFormatter.format_snapshot(snapshot_data, format: options[:format].to_sym)
      write_snapshot_output(output)
    end

    private

    def prompt_snapshot_data
      say ''
      say 'Recording snapshot...', :green
      say ''

      {
        time: Time.now,
        ai_involved: ask_snapshot_choice('AI involved?', MetrFormatter::AI_INVOLVED_OPTIONS),
        focus: ask_snapshot_choice('Focus level:', MetrFormatter::FOCUS_OPTIONS),
        same_task: ask_yes_no_dk('Same task as last snapshot?'),
        ai_vanished_impact: ask_snapshot_choice('If AI vanished:', MetrFormatter::AI_VANISHED_OPTIONS),
        what: ask('What are you doing (one line):'),
        type: ask_snapshot_choice('Type:', MetrFormatter::TASK_TYPES)
      }
    end

    def ask_snapshot_choice(prompt, choices)
      say prompt
      choices.each_with_index { |c, i| say "  #{i + 1}. #{c}" }
      response = ask("Select (1-#{choices.length}):")
      idx = response.to_i - 1
      idx >= 0 && idx < choices.length ? choices[idx] : choices.first
    end

    def ask_yes_no_dk(prompt)
      say prompt
      say '  1. Yes'
      say '  2. No'
      say "  3. Don't know"
      response = ask('Select (1-3):')
      case response.to_i
      when 1 then 'Yes'
      when 2 then 'No'
      else "Don't know"
      end
    end

    def write_snapshot_output(output)
      if options[:output]
        mode = options[:append] ? 'a' : 'w'
        File.open(options[:output], mode) do |f|
          f.puts output
          f.puts '' if options[:append] # Add blank line between snapshots
        end
        action = options[:append] ? 'Appended to' : 'Written to'
        say "#{action}: #{options[:output]}", :green
      else
        say ''
        say output
      end
    end
  end
end
