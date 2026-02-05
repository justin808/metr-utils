# frozen_string_literal: true

require 'thor'
require 'json'

module TogglDb
  class CLI < Thor
    # Subcommand for database exploration (advanced)
    class DbCommands < Thor
      class_option :database, aliases: '-d', type: :string,
                              desc: 'Path to Toggl database (default: auto-discover)'
      class_option :format, aliases: '-f', type: :string, enum: %w[table json csv],
                            default: 'table', desc: 'Output format'

      def self.exit_on_failure?
        true
      end

      desc 'tables', 'List all tables in the database'
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
      option :limit, aliases: '-l', type: :numeric, default: 10,
                     desc: 'Number of rows to display'
      def sample(table)
        db = open_database

        unless db.tables.include?(table)
          error_and_exit("Table '#{table}' not found. Use 'toggl_db db tables' to list available tables.")
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

      private

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
          print_table_data(data, columns)
        end
      end

      def print_table_data(data, columns)
        widths = columns.map do |col|
          values = data.map { |row| row[col].to_s }
          [col.length, values.map(&:length).max || 0].max
        end

        header = columns.zip(widths).map { |col, w| col.ljust(w) }.join('  ')
        say header, :green
        say '-' * header.length

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
    end
  end
end
