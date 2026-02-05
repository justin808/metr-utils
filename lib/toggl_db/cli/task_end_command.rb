# frozen_string_literal: true

require 'time'

module TogglDb
  class CLI < Thor
    # Core Data epoch: 2001-01-01 00:00:00 UTC
    CORE_DATA_EPOCH = Time.utc(2001, 1, 1).to_i

    # Apps considered AI tools for percentage calculation
    AI_APPS = %w[Claude ChatGPT Gemini Copilot Cursor].freeze

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

      Examples:
        $ toggl_db task-end                    # Show today's entries, pick one
        $ toggl_db task-end --from "8:30am"    # From 8:30am to now
        $ toggl_db task-end --interactive      # Prompt for estimates
    DESC
    option :from, type: :string, desc: 'Start time (e.g., "8:30am", "2024-01-15 09:00")'
    option :to, type: :string, desc: 'End time (e.g., "now", "5:30pm")'
    option :interactive, aliases: '-i', type: :boolean, default: false,
                         desc: 'Prompt for Without-AI estimate and Quality rating'
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

      print_task_end_report(combined, app_breakdown, ai_percentage)
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

    def print_task_end_report(entry, app_breakdown, ai_percentage)
      estimates = extract_or_prompt_estimates(entry[:metadata])
      say ''
      say '=' * 60, :green
      say 'TASK END', :green
      say "Task: #{entry[:task_name]}"
      say "Clock: #{format_time_range(entry)}"
      say "Focused time: #{format_duration(entry[:duration_seconds])}"
      say "AI %: #{ai_percentage}% (#{format_ai_details(app_breakdown)})"
      say "With-AI estimate: #{estimates[:with_ai]}" if estimates[:with_ai]
      say "Without-AI estimate: #{estimates[:without_ai]}"
      say "Quality: #{estimates[:quality]}"
      say "Notes: App breakdown - #{format_app_breakdown(app_breakdown)}" if app_breakdown.any?
      say '=' * 60, :green
    end

    def extract_or_prompt_estimates(metadata)
      # Try to parse metadata first: "30 min, 4 hours without"
      if metadata
        parsed = parse_metadata_estimates(metadata)
        return parsed if parsed
      end

      return { with_ai: nil, without_ai: '[YOU FILL IN]', quality: '[1-5]' } unless options[:interactive]

      say ''
      {
        with_ai: nil,
        without_ai: ask('Without-AI estimate (e.g., "4 hours"):'),
        quality: ask('Quality rating (1-5):')
      }
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
      "#{entry[:start_time].strftime('%I:%M %p')} - #{entry[:end_time].strftime('%I:%M %p')}"
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
