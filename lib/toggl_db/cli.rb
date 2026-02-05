# frozen_string_literal: true

require 'thor'
require 'json'
require_relative '../toggl_db'

module TogglDb
  class CLI < Thor
    class_option :database, aliases: '-d', type: :string,
                            desc: 'Path to Toggl database (default: auto-discover)'
    class_option :format, aliases: '-f', type: :string, enum: %w[table json csv],
                          default: 'table', desc: 'Output format'

    def self.exit_on_failure?
      true
    end

    desc 'find', 'Find and display the Toggl database location'
    long_desc <<~DESC
      Searches for the Toggl Track SQLite database in standard locations.

      Search order:
        1. Path specified via --database option
        2. TOGGL_DB_PATH environment variable
        3. Config file database_path setting
        4. Platform-specific standard locations

      If found via auto-discovery, offers to save the path to config.

      Example:
        $ toggl_db find
        $ toggl_db config set database_path ~/toggl.db
        $ TOGGL_DB_PATH=/custom/path.db toggl_db find
    DESC
    option :save, aliases: '-s', type: :boolean, default: false,
                  desc: 'Save discovered path to config without prompting'
    def find
      # Check if path will come from auto-discovery
      cli_path = options[:database]
      env_path = ENV.fetch('TOGGL_DB_PATH', nil)
      config_path = Config['database_path']
      was_auto_discovered = cli_path.nil? && env_path.nil? && config_path.nil?

      path = TogglDb.find_database(cli_path)
      say 'Found Toggl database:', :green
      say "  #{path}"
      say "\nFile size: #{format_size(path.size)}"
      say "Modified:  #{path.mtime.strftime('%Y-%m-%d %H:%M:%S')}"

      # Offer to save if auto-discovered
      return unless was_auto_discovered

      say ''
      should_save = options[:save] || yes?('Save this path to config for future use? [y/N]')
      if should_save
        save_database_path(path)
      else
        say "Tip: Run 'toggl_db find --save' or 'toggl_db config set database_path #{path}'", :cyan
      end
    rescue DatabaseNotFoundError => e
      error_and_exit(e.message)
    end

    desc 'tables', 'List all tables in the database'
    long_desc <<~DESC
      Lists all tables in the Toggl database with optional row counts.

      Example:
        $ toggl_db tables
        $ toggl_db tables --counts
    DESC
    option :counts, aliases: '-c', type: :boolean, default: false,
                    desc: 'Include row counts for each table'
    def tables
      db = open_database
      table_names = db.tables

      if options[:counts]
        data = table_names.map do |name|
          { 'table' => name, 'rows' => db.count(name) }
        end
        output_data(data, columns: %w[table rows])
      else
        case options[:format]
        when 'json'
          say JSON.pretty_generate(table_names)
        when 'csv'
          table_names.each { |t| say t }
        else
          say 'Tables in database:', :green
          table_names.each { |t| say "  #{t}" }
        end
      end
    ensure
      db&.close
    end

    desc 'schema TABLE', 'Show schema for a table'
    long_desc <<~DESC
      Displays column information for the specified table including
      column names, types, nullability, and default values.

      Example:
        $ toggl_db schema time_entries
        $ toggl_db schema projects --format json
    DESC
    def schema(table)
      db = open_database
      columns = db.describe_table(table)

      error_and_exit("Table '#{table}' not found or has no columns") if columns.empty?

      formatted = columns.map do |col|
        {
          'name' => col['name'],
          'type' => col['type'] || 'ANY',
          'nullable' => col['notnull'].zero? ? 'YES' : 'NO',
          'default' => col['dflt_value'] || 'NULL',
          'pk' => col['pk'].positive? ? 'YES' : ''
        }
      end

      output_data(formatted, columns: %w[name type nullable default pk])
    rescue ArgumentError => e
      error_and_exit(e.message)
    ensure
      db&.close
    end

    desc 'query SQL', 'Execute a read-only SQL query'
    long_desc <<~DESC
      Executes a SELECT query against the Toggl database.
      Only read-only queries are allowed - any modification
      attempts will be rejected.

      Example:
        $ toggl_db query "SELECT * FROM time_entries LIMIT 5"
        $ toggl_db query "SELECT * FROM projects" --format json
        $ toggl_db query "SELECT * FROM tasks" --format csv
    DESC
    option :limit, aliases: '-l', type: :numeric, desc: 'Limit number of results'
    def query(sql)
      db = open_database

      # Add LIMIT if specified and not already present
      sql = "#{sql.chomp(';')} LIMIT #{options[:limit]}" if options[:limit] && !sql.upcase.include?('LIMIT')

      results = db.query(sql)

      if results.empty?
        say 'No results', :yellow
        return
      end

      output_data(results)
    rescue ReadOnlyDatabaseError => e
      error_and_exit("Read-only violation: #{e.message}")
    rescue SQLite3::SQLException => e
      error_and_exit("SQL error: #{e.message}")
    ensure
      db&.close
    end

    desc 'sample TABLE', 'Show sample rows from a table'
    long_desc <<~DESC
      Displays sample rows from the specified table.
      Useful for exploring table contents.

      Example:
        $ toggl_db sample time_entries
        $ toggl_db sample projects --limit 20
    DESC
    option :limit, aliases: '-l', type: :numeric, default: 10,
                   desc: 'Number of rows to display'
    def sample(table)
      db = open_database

      # Validate table exists
      unless db.tables.include?(table)
        error_and_exit("Table '#{table}' not found. Use 'toggl_db tables' to list available tables.")
      end

      results = db.query("SELECT * FROM #{table} LIMIT #{options[:limit]}")

      if results.empty?
        say "Table '#{table}' is empty", :yellow
        return
      end

      output_data(results)
    ensure
      db&.close
    end

    desc 'search TERM', 'Search for tables or columns matching a term'
    long_desc <<~DESC
      Searches table and column names for the given term.
      Useful for discovering where data might be stored.

      Example:
        $ toggl_db search project
        $ toggl_db search time
    DESC
    def search(term)
      db = open_database
      term_lower = term.downcase
      matches = []

      db.tables.each do |table|
        table_matches = table.downcase.include?(term_lower)
        columns = db.describe_table(table)

        matching_columns = columns.select { |c| c['name'].downcase.include?(term_lower) }

        matches << { type: 'table', name: table, context: nil } if table_matches

        matching_columns.each do |col|
          matches << { type: 'column', name: col['name'], context: "in #{table}" }
        end
      end

      if matches.empty?
        say "No matches found for '#{term}'", :yellow
        return
      end

      say "Matches for '#{term}':", :green
      matches.each do |m|
        context = m[:context] ? " (#{m[:context]})" : ''
        say "  #{m[:type].ljust(6)} #{m[:name]}#{context}"
      end
    ensure
      db&.close
    end

    desc 'locations', 'Show database search locations for this platform'
    long_desc <<~DESC
      Shows all locations where toggl_db searches for the database.

      Search priority (highest to lowest):
        1. --database command-line option
        2. TOGGL_DB_PATH environment variable
        3. Config file database_path setting
        4. Platform-specific standard locations
    DESC
    def locations
      say 'Database search priority:', :green
      say ''

      say '1. Command-line option (--database, -d)'
      say '   Use: toggl_db <command> -d /path/to/db', :cyan
      say ''

      say '2. Environment variable:'
      env_path = ENV.fetch('TOGGL_DB_PATH', nil)
      if env_path
        say "   TOGGL_DB_PATH=#{env_path}", :green
      else
        say '   TOGGL_DB_PATH (not set)', :yellow
      end
      say ''

      say '3. Config file:'
      say "   #{Config.path}", :cyan
      config_db = Config['database_path']
      if config_db
        exists = File.exist?(config_db) ? ' (exists)' : ' (NOT FOUND)'
        color = File.exist?(config_db) ? :green : :red
        say "   database_path=#{config_db}#{exists}", color
      else
        say '   database_path (not set)', :yellow
      end
      say ''

      say '4. Auto-discovery locations:'
      TogglDb.search_paths.each do |path|
        exists = path.exist? ? ' (exists)' : ''
        color = path.exist? ? :green : :yellow
        say "   #{path}#{exists}", color
      end
    end

    desc 'version', 'Show version information'
    def version
      say 'toggl_db 0.1.0'
      say 'Read-only Toggl database explorer'
    end

    desc 'config SUBCOMMAND', 'Manage configuration'
    long_desc <<~DESC
      Manage toggl_db configuration settings.

      Subcommands:
        config list              - Show all settings
        config get KEY           - Get a specific setting
        config set KEY VALUE     - Set a setting
        config path              - Show config file location
        config init              - Create config file with defaults

      Available settings:
        database_path    - Path to Toggl database (default: auto-discover)
        default_format   - Output format: table, json, csv (default: table)
        default_limit    - Default row limit for queries (default: 100)

      Example:
        $ toggl_db config set database_path ~/toggl.db
        $ toggl_db config get database_path
        $ toggl_db config list
    DESC
    def config(subcommand = 'list', key = nil, value = nil)
      case subcommand
      when 'list'
        config_list
      when 'get'
        error_and_exit('Missing key. Usage: config get KEY') unless key
        config_get(key)
      when 'set'
        error_and_exit('Missing key and value. Usage: config set KEY VALUE') unless key && value
        config_set(key, value)
      when 'path'
        config_path_cmd
      when 'init'
        config_init
      else
        error_and_exit("Unknown config subcommand: #{subcommand}")
      end
    end

    private

    def config_list
      say "Config file: #{Config.path}", :green
      say Config.exists? ? '(exists)' : '(not created yet)', Config.exists? ? :green : :yellow
      say ''

      Config.to_h.each do |key, val|
        display_val = val.nil? ? '(not set)' : val.to_s
        color = val.nil? ? :yellow : :white
        say "  #{key.ljust(20)} #{display_val}", color
      end
    end

    def config_get(key)
      unless Config::DEFAULTS.key?(key)
        error_and_exit("Unknown config key: #{key}\nValid keys: #{Config::DEFAULTS.keys.join(', ')}")
      end

      val = Config[key]
      if val.nil?
        say '(not set)', :yellow
      else
        say val
      end
    end

    def config_set(key, value)
      unless Config::DEFAULTS.key?(key)
        error_and_exit("Unknown config key: #{key}\nValid keys: #{Config::DEFAULTS.keys.join(', ')}")
      end

      # Type coercion
      value = case key
              when 'default_limit'
                value.to_i
              when 'database_path'
                %w[nil null].include?(value) ? nil : File.expand_path(value)
              else
                value
              end

      # Validate database_path exists if set
      error_and_exit("Database file not found: #{value}") if key == 'database_path' && value && !File.exist?(value)

      Config[key] = value
      Config.save
      say "Set #{key} = #{value.nil? ? '(cleared)' : value}", :green
    end

    def config_path_cmd
      say Config.path
    end

    def config_init
      if Config.exists?
        say "Config file already exists: #{Config.path}", :yellow
        say 'Current settings:'
        config_list
        return
      end

      Config.save
      say "Created config file: #{Config.path}", :green
      say "\nDefault settings:"
      config_list
    end

    def save_database_path(path)
      Config['database_path'] = path.to_s
      Config.save
      say "Saved to config: database_path=#{path}", :green
    end

    def open_database
      TogglDb::Database.new(options[:database])
    rescue DatabaseNotFoundError => e
      error_and_exit(e.message)
    end

    def error_and_exit(message)
      say_error "Error: #{message}", :red
      exit 1
    end

    def say_error(message, color = nil)
      warn set_color(message, color) if color
      warn message unless color
    end

    def output_data(data, columns: nil)
      return if data.empty?

      columns ||= data.first.keys

      case options[:format]
      when 'json'
        say JSON.pretty_generate(data)
      when 'csv'
        say columns.join(',')
        data.each do |row|
          say columns.map { |c| csv_escape(row[c]) }.join(',')
        end
      else
        print_table(data, columns)
      end
    end

    def print_table(data, columns)
      # Calculate column widths
      widths = columns.map do |col|
        values = data.map { |row| row[col].to_s }
        [col.length, values.map(&:length).max || 0].max
      end

      # Print header
      header = columns.zip(widths).map { |col, w| col.ljust(w) }.join('  ')
      say header, :green
      say '-' * header.length

      # Print rows
      data.each do |row|
        line = columns.zip(widths).map { |col, w| truncate(row[col].to_s, w).ljust(w) }.join('  ')
        say line
      end

      say "\n#{data.length} row(s)"
    end

    def truncate(str, max_length)
      return str if str.length <= max_length || max_length < 4

      "#{str[0, max_length - 3]}..."
    end

    def csv_escape(value)
      str = value.to_s
      if str.include?(',') || str.include?('"') || str.include?("\n")
        "\"#{str.gsub('"', '""')}\""
      else
        str
      end
    end

    def format_size(bytes)
      units = %w[B KB MB GB]
      unit_index = 0
      size = bytes.to_f

      while size >= 1024 && unit_index < units.length - 1
        size /= 1024
        unit_index += 1
      end

      format('%.1f %s', size, units[unit_index])
    end
  end
end
