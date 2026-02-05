# frozen_string_literal: true

require 'time'
require_relative 'metr_formatter'
require_relative '../task_store'

module TogglDb
  class CLI < Thor
    # Core Data epoch: 2001-01-01 00:00:00 UTC
    CORE_DATA_EPOCH = Time.utc(2001, 1, 1).to_i

    # Apps considered AI tools for percentage calculation
    AI_APPS = %w[Claude ChatGPT Gemini Copilot Cursor Conductor].freeze

    # Metadata separator in task descriptions
    METADATA_SEPARATOR = ' -- '

    desc 'task-end', 'Generate a Metr TASK END report'
    long_desc <<~DESC
      Generates a TASK END report in Metr's required format for productivity research.

      Task descriptions can include metadata after ' -- ':
        "Task name -- 30 min, 4 hours without"
        "Task name -- continue" (for continuation entries)

      Selection supports ranges and comma-separated values:
        1-5     (entries 1 through 5)
        1,3,5   (entries 1, 3, and 5)
        1-3,5   (entries 1 through 3, plus 5)

      Use --format metr for strict Metr format output.

      Examples:
        $ toggl_db task-end                    # Show today's entries, pick one
        $ toggl_db task-end --from "8:30am"    # From 8:30am to now
        $ toggl_db task-end --interactive      # Prompt for all fields
        $ toggl_db task-end --format metr      # Output in strict Metr format
        $ toggl_db task-end -o ~/report.txt    # Write to file
    DESC
    option :from, type: :string, desc: 'Start time (e.g., "8:30am", "2024-01-15 09:00")'
    option :to, type: :string, desc: 'End time (e.g., "now", "5:30pm")'
    option :interactive, aliases: '-i', type: :boolean, default: false,
                         desc: 'Prompt for all Metr fields interactively'
    option :format, aliases: '-f', type: :string, enum: %w[default metr], default: 'default',
                    desc: 'Output format (default or metr)'
    option :output, aliases: '-o', type: :string, desc: 'Write output to file'
    option :task_id, type: :numeric, desc: 'Link to a tracked task ID'
    option :database, aliases: '-d', type: :string,
                      desc: 'Path to Toggl database (default: auto-discover)'
    def task_end
      db = open_database
      entries = fetch_time_entries(db, options[:from], options[:to])

      if entries.empty?
        say 'No time entries found for the specified period.', :yellow
        say 'Try: toggl_db task-end --from "8:00am"'
        return
      end

      selected = entries.length == 1 ? entries : select_entries(entries)
      return if selected.nil? || selected.empty?

      combined = combine_selected_entries(selected)
      activities = fetch_activities(db, combined[:start_ts], combined[:end_ts])
      app_breakdown = calculate_app_breakdown(activities)
      ai_percentage = calculate_ai_percentage(app_breakdown)

      # Determine task ID from option, current task, or prompt
      task_id = determine_task_id

      # Build report data
      report_data = build_report_data(combined, app_breakdown, ai_percentage, task_id)

      # Output in requested format
      output_task_end_report(report_data)
    rescue DatabaseNotFoundError => e
      error_and_exit(e.message)
    ensure
      db&.close
    end

    private

    def fetch_time_entries(db, from_time, to_time)
      conditions, params = build_time_conditions(from_time, to_time)
      results = execute_time_entries_query(db, conditions, params)
      results.map { |row| build_entry_hash(row) }
    end

    def build_time_conditions(from_time, to_time)
      conditions = []
      params = []

      from_ts = from_time ? parse_time_to_core_data(from_time) : today_start_timestamp
      conditions << 'ZSTART_CURRENT >= ?'
      params << from_ts

      if to_time && to_time.downcase != 'now'
        conditions << 'ZSTART_CURRENT <= ?'
        params << parse_time_to_core_data(to_time)
      end

      [conditions, params]
    end

    def today_start_timestamp
      Time.now.to_date.to_time.to_i - CORE_DATA_EPOCH
    end

    def execute_time_entries_query(db, conditions, params)
      where_clause = "WHERE #{conditions.join(' AND ')}"
      sql = <<~SQL
        SELECT ZSTART_CURRENT, ZDURATION_CURRENT, ZDESCRIPTION_CURRENT, ZPROJECT
        FROM ZMANAGEDTIMEENTRY #{where_clause}
        ORDER BY ZSTART_CURRENT DESC
      SQL
      db.query(sql, *params)
    end

    def build_entry_hash(row)
      start_ts = row['ZSTART_CURRENT']
      duration = row['ZDURATION_CURRENT'] || 0
      description = row['ZDESCRIPTION_CURRENT'] || '(no description)'
      task_name, metadata = parse_task_description(description)

      {
        description: description,
        task_name: task_name,
        metadata: metadata,
        start_ts: start_ts,
        end_ts: start_ts + duration,
        start_time: core_data_to_time(start_ts),
        end_time: core_data_to_time(start_ts + duration),
        duration_seconds: duration,
        project_id: row['ZPROJECT']
      }
    end

    def parse_task_description(description)
      return [description, nil] unless description.include?(METADATA_SEPARATOR)

      parts = description.split(METADATA_SEPARATOR, 2)
      task_name = parts[0].strip
      metadata = parts[1]&.strip

      # "continue" is not real metadata, just a marker
      metadata = nil if metadata&.downcase == 'continue'

      [task_name, metadata]
    end

    def fetch_activities(db, start_ts, end_ts)
      sql = <<~SQL
        SELECT ZSTART, ZEND, ZFILENAME, ZTITLE
        FROM ZMANAGEDACTIVITY
        WHERE ZSTART >= ? AND ZEND <= ?
        ORDER BY ZSTART
      SQL
      db.query(sql, start_ts, end_ts)
    end

    def calculate_app_breakdown(activities)
      breakdown = Hash.new(0.0)
      activities.each do |activity|
        app = activity['ZFILENAME'] || 'Unknown'
        duration = (activity['ZEND'] || 0) - (activity['ZSTART'] || 0)
        breakdown[app] += duration
      end

      total = breakdown.values.sum
      return {} if total.zero?

      breakdown.transform_values { |v| (v / total * 100).round(1) }
               .sort_by { |_, v| -v }
               .to_h
    end

    def calculate_ai_percentage(app_breakdown)
      app_breakdown.sum do |app, percentage|
        ai_app?(app) ? percentage : 0.0
      end.round(1)
    end

    def ai_app?(app_name)
      AI_APPS.any? { |ai_app| app_name.downcase.include?(ai_app.downcase) }
    end

    def select_entries(entries)
      sorted_by_title = false
      display_list = entries.dup

      loop do
        display_entry_choices(display_list, sorted_by_title)
        choice = ask("Select (1-#{display_list.length}), range (1-5), A=all, T=toggle sort:")

        return nil if choice.nil? || choice.strip.empty?

        if choice.strip.downcase == 't'
          sorted_by_title = !sorted_by_title
          display_list = sorted_by_title ? entries.sort_by { |e| e[:task_name] } : entries.dup
          next
        end

        return parse_selection(choice, display_list)
      end
    end

    def display_entry_choices(entries, sorted_by_title)
      sort_label = sorted_by_title ? ' (sorted by title)' : ' (sorted by time)'
      say "\nTime entries#{sort_label}:", :green
      say ''
      entries.each_with_index do |entry, idx|
        say "  #{idx + 1}. #{entry[:task_name]}"
        metadata_hint = entry[:metadata] ? " [#{entry[:metadata]}]" : ''
        say "     #{format_time_range(entry)} (#{format_duration(entry[:duration_seconds])})#{metadata_hint}", :cyan
      end
      say ''
      say '  A. Combine all  |  T. Toggle sort by title/time'
      say ''
    end

    def parse_selection(choice, entries)
      return entries if choice.strip.downcase == 'a'

      indices = parse_selection_indices(choice, entries.length)
      return nil if indices.empty?

      indices.map { |i| entries[i] }
    end

    def parse_selection_indices(choice, max)
      indices = []

      # Split by comma, then handle ranges
      choice.split(',').each do |part|
        part = part.strip
        if part.include?('-')
          # Range: "1-5"
          range_parts = part.split('-', 2)
          start_idx = range_parts[0].to_i - 1
          end_idx = range_parts[1].to_i - 1
          (start_idx..end_idx).each { |i| indices << i if i >= 0 && i < max }
        else
          # Single number
          idx = part.to_i - 1
          indices << idx if idx >= 0 && idx < max
        end
      end

      indices.uniq.sort
    end

    def combine_selected_entries(entries)
      # Find the entry with metadata (the original task, not continuations)
      entry_with_metadata = entries.find { |e| e[:metadata] }

      # If no metadata found, use the oldest entry (last in DESC order = first tracked)
      primary_entry = entry_with_metadata || entries.last

      {
        task_name: primary_entry[:task_name],
        metadata: primary_entry[:metadata],
        start_ts: entries.map { |e| e[:start_ts] }.min,
        end_ts: entries.map { |e| e[:end_ts] }.max,
        start_time: core_data_to_time(entries.map { |e| e[:start_ts] }.min),
        end_time: core_data_to_time(entries.map { |e| e[:end_ts] }.max),
        duration_seconds: entries.sum { |e| e[:duration_seconds] }
      }
    end

    def determine_task_id
      return options[:task_id] if options[:task_id]

      current = TaskStore.current_task
      return current['id'] if current

      nil
    end

    def build_report_data(entry, app_breakdown, ai_percentage, task_id)
      total_minutes = (entry[:duration_seconds] / 60.0).round
      used_ai = ai_percentage.positive?

      # Get user-provided fields if interactive or metr format
      user_fields = prompt_task_end_fields(entry, total_minutes, ai_percentage)

      {
        task_id: task_id,
        task_name: entry[:task_name],
        end_time: entry[:end_time],
        clock_range: format_time_range(entry),
        used_ai: used_ai,
        total_elapsed_minutes: total_minutes,
        active_work_minutes: user_fields[:active_work_minutes],
        waiting_ai_minutes: user_fields[:waiting_ai_minutes],
        outcome: user_fields[:outcome],
        ai_percentage: ai_percentage,
        ai_turns: user_fields[:ai_turns],
        without_ai_minutes: user_fields[:without_ai_minutes],
        quality_vs_self: user_fields[:quality_vs_self],
        with_ai_estimate: user_fields[:with_ai_estimate],
        notes: format_app_breakdown(app_breakdown),
        ai_details: format_ai_details(app_breakdown),
        app_breakdown_text: format_app_breakdown(app_breakdown)
      }
    end

    def prompt_task_end_fields(entry, total_minutes, ai_percentage)
      # Try to parse metadata first
      parsed = parse_metadata_estimates(entry[:metadata]) if entry[:metadata]
      used_ai = ai_percentage.positive?

      # If not interactive and not metr format, return minimal data
      unless options[:interactive] || options[:format] == 'metr'
        return {
          with_ai_estimate: parsed&.dig(:with_ai),
          without_ai_minutes: parsed&.dig(:without_ai) || '[YOU FILL IN]',
          quality_vs_self: parsed&.dig(:quality) || '[1-5]',
          active_work_minutes: nil,
          waiting_ai_minutes: nil,
          outcome: nil,
          ai_turns: nil
        }
      end

      say ''
      say 'Collecting Metr task end data...', :green
      say ''

      # TIME BREAKDOWN
      active_work = ask_numeric_field('Active work time (minutes):', default: total_minutes)
      waiting_ai = used_ai ? ask_numeric_field('Waiting/reviewing AI time (minutes):', default: 0) : 0

      # OUTCOME
      outcome = ask_choice_field('Outcome:', MetrFormatter::OUTCOMES)

      # AI fields
      ai_turns = used_ai ? ask_numeric_field('Number of AI turns:') : nil

      # Without AI estimate
      without_ai_default = parsed&.dig(:without_ai)
      without_ai = ask_numeric_field('Without AI would take (minutes):', default: without_ai_default&.to_i)

      # Quality
      quality = used_ai ? ask_choice_field('Quality vs yourself:', MetrFormatter::QUALITY_RATINGS) : nil

      {
        with_ai_estimate: parsed&.dig(:with_ai),
        without_ai_minutes: without_ai,
        quality_vs_self: quality,
        active_work_minutes: active_work,
        waiting_ai_minutes: waiting_ai,
        outcome: outcome,
        ai_turns: ai_turns
      }
    end

    def ask_numeric_field(prompt, default: nil)
      default_hint = default ? " [#{default}]" : ''
      response = ask("#{prompt}#{default_hint}")
      return default if response.strip.empty? && default

      response.to_i
    end

    def ask_choice_field(prompt, choices, default: nil)
      say prompt
      choices.each_with_index { |c, i| say "  #{i + 1}. #{c}" }
      default_idx = default ? choices.index(default) + 1 : nil
      default_hint = default_idx ? " [#{default_idx}]" : ''
      response = ask("Select (1-#{choices.length})#{default_hint}:")

      return default if response.strip.empty? && default

      idx = response.to_i - 1
      idx >= 0 && idx < choices.length ? choices[idx] : (default || choices.first)
    end

    def output_task_end_report(data)
      output = MetrFormatter.format_task_end(data, format: options[:format].to_sym)

      if options[:output]
        File.write(options[:output], "#{output}\n")
        say "Output written to: #{options[:output]}", :green
      else
        say ''
        say output
      end

      # Update task store if we have a task ID
      update_task_store(data) if data[:task_id]
    end

    def update_task_store(data)
      TaskStore.end_task(data[:task_id], {
                           outcome: data[:outcome],
                           actual_elapsed_minutes: data[:total_elapsed_minutes],
                           active_work_minutes: data[:active_work_minutes],
                           waiting_ai_minutes: data[:waiting_ai_minutes],
                           ai_percentage: data[:ai_percentage],
                           ai_turns: data[:ai_turns],
                           without_ai_minutes: data[:without_ai_minutes],
                           quality_vs_self: data[:quality_vs_self],
                           notes: data[:notes]
                         })
    end

    def parse_metadata_estimates(metadata)
      # Expected format: "30 min, 4 hours without" or "30min, 4hr without"
      # First part = WITH AI estimate, second part = WITHOUT AI estimate
      return nil unless metadata.include?(',')

      parts = metadata.split(',', 2).map(&:strip)
      return nil if parts.length < 2

      with_ai = parts[0].strip
      # The second part: extract the time portion (remove "without" suffix if present)
      without_ai = parts[1].sub(/\s*without.*$/i, '').strip

      {
        with_ai: with_ai,
        without_ai: without_ai,
        quality: '[1-5]' # Quality still needs to be filled in
      }
    end

    def format_time_range(entry)
      same_day = entry[:start_time].to_date == entry[:end_time].to_date
      if same_day
        # Same day: show date once, then just times
        date_str = entry[:start_time].strftime('%Y-%m-%d')
        start_time = entry[:start_time].strftime('%I:%M %p')
        end_time = entry[:end_time].strftime('%I:%M %p')
        "#{date_str} #{start_time} - #{end_time}"
      else
        # Different days: show full date+time for both
        start_str = entry[:start_time].strftime('%Y-%m-%d %I:%M %p')
        end_str = entry[:end_time].strftime('%Y-%m-%d %I:%M %p')
        "#{start_str} - #{end_str}"
      end
    end

    def format_ai_details(app_breakdown)
      ai_apps = app_breakdown.select { |app, _| ai_app?(app) }
      return 'no AI apps detected' if ai_apps.empty?

      ai_apps.map { |app, pct| "#{app} #{pct}%" }.join(', ')
    end

    def format_app_breakdown(app_breakdown)
      # Show all apps, but filter out tiny ones (<1%)
      significant = app_breakdown.select { |_, pct| pct >= 1.0 }
      significant.map { |app, pct| "#{app}: #{pct}%" }.join(', ')
    end

    def parse_time_to_core_data(time_str)
      parse_time_string(time_str).to_i - CORE_DATA_EPOCH
    end

    def parse_time_string(time_str)
      return Time.now if time_str.downcase == 'now'

      if time_str.match?(/^\d{1,2}:\d{2}\s*(am|pm)?$/i)
        Time.parse("#{Time.now.to_date} #{time_str}")
      else
        Time.parse(time_str)
      end
    rescue ArgumentError
      raise ArgumentError, "Cannot parse time: #{time_str}"
    end

    def core_data_to_time(timestamp)
      Time.at(timestamp + CORE_DATA_EPOCH)
    end

    def format_duration(seconds)
      hours = seconds / 3600.0
      hours >= 1 ? format('%.1fhr', hours) : "#{(seconds / 60).round}min"
    end
  end
end
