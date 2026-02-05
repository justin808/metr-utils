# frozen_string_literal: true

# Toggl Database Access Module - READ-ONLY
#
# This module provides safe, read-only access to the Toggl Track SQLite database.
# All connections are opened in read-only mode to prevent accidental modifications.

require 'sqlite3'
require 'pathname'
require_relative 'toggl_db/config'

module TogglDb
  class ReadOnlyDatabaseError < StandardError; end
  class DatabaseNotFoundError < StandardError; end

  # SQL keywords that indicate modification attempts
  FORBIDDEN_KEYWORDS = %w[
    INSERT UPDATE DELETE DROP ALTER CREATE REPLACE TRUNCATE ATTACH DETACH
  ].freeze

  class << self
    # Find the Toggl database file.
    #
    # Priority:
    # 1. custom_path argument
    # 2. TOGGL_DB_PATH environment variable
    # 3. Config file (database_path setting)
    # 4. Auto-discovery from standard locations
    #
    # @param custom_path [String, nil] Optional explicit path to database
    # @return [Pathname] Path to the database file
    # @raise [DatabaseNotFoundError] If database cannot be found
    def find_database(custom_path = nil)
      # Priority 1: Custom path argument
      if custom_path
        path = Pathname.new(custom_path)
        return path if path.exist?

        raise DatabaseNotFoundError, "Specified database not found: #{custom_path}"
      end

      # Priority 2: Environment variable
      env_path = ENV.fetch('TOGGL_DB_PATH', nil)
      if env_path
        path = Pathname.new(env_path)
        return path if path.exist?

        raise DatabaseNotFoundError, "TOGGL_DB_PATH points to non-existent file: #{env_path}"
      end

      # Priority 3: Config file
      config_path = Config['database_path']
      if config_path
        path = Pathname.new(config_path)
        return path if path.exist?

        raise DatabaseNotFoundError, "Config database_path points to non-existent file: #{config_path}"
      end

      # Priority 4: Auto-discovery
      search_paths.each do |search_dir|
        next unless search_dir.exist?

        %w[*.db *.sqlite *.sqlite3].each do |pattern|
          search_dir.glob(pattern).each do |db_file|
            return db_file if db_file.file?
          end
        end
      end

      raise DatabaseNotFoundError,
            "Toggl database not found.\n" \
            "Searched locations:\n#{search_paths.map { |p| "  - #{p}" }.join("\n")}\n\n" \
            "Set database_path in config (#{Config.path}),\n" \
            'TOGGL_DB_PATH environment variable, or use --database option.'
    end

    # Execute a read-only query against the Toggl database.
    #
    # @param sql [String] SQL query (SELECT only)
    # @param db_path [String, nil] Optional path to database
    # @return [Array<Hash>] Array of result rows as hashes
    def query(sql, db_path: nil)
      Database.new(db_path).query(sql)
    end

    # Return platform-specific paths where Toggl database may be located.
    # @return [Array<Pathname>]
    def search_paths
      home = Pathname.new(Dir.home)
      paths = []

      case RbConfig::CONFIG['host_os']
      when /darwin/i # macOS
        # Search for any Toggl-related Group Containers (handles Team ID changes)
        group_containers = home / 'Library/Group Containers'
        if group_containers.exist?
          group_containers.glob('*toggl*').each do |container|
            paths.push(container / 'production')
          end
        end
        # Legacy Application Support locations
        paths.push(
          home / 'Library/Application Support/Toggl Track',
          home / 'Library/Application Support/Toggl Desktop',
          home / 'Library/Application Support/toggldesktop'
        )
      when /linux/i
        paths.push(
          home / '.local/share/toggl',
          home / '.config/Toggl Track'
        )
      when /mswin|mingw|cygwin/i # Windows
        appdata = ENV.fetch('APPDATA', nil)
        if appdata
          appdata_path = Pathname.new(appdata)
          paths.push(
            appdata_path / 'Toggl Track',
            appdata_path / 'TogglDesktop'
          )
        end
      end

      paths
    end
  end

  # Read-only interface to the Toggl SQLite database.
  #
  # All connections are opened in read-only mode. Any attempt to execute
  # modifying queries will raise ReadOnlyDatabaseError.
  class Database
    attr_reader :db_path

    # Initialize read-only database connection.
    #
    # @param db_path [String, nil] Optional path to database. If not provided, will auto-discover.
    def initialize(db_path = nil)
      @db_path = TogglDb.find_database(db_path)
      @connection = nil
    end

    # Execute a read-only SQL query.
    #
    # @param sql [String] SQL query (must be SELECT or other read-only operation)
    # @param params [Array] Query parameters
    # @return [Array<Hash>] Array of result rows as hashes
    # @raise [ReadOnlyDatabaseError] If query attempts to modify data
    def query(sql, *params)
      validate_query!(sql)
      connection.execute(sql, params).map { |row| row_to_hash(row) }
    end

    # Execute query and return first result.
    #
    # @param sql [String] SQL query
    # @param params [Array] Query parameters
    # @return [Hash, nil] First result row or nil
    def query_single(sql, *params)
      validate_query!(sql)
      row = connection.get_first_row(sql, params)
      row ? row_to_hash(row) : nil
    end

    # List all tables in the database.
    #
    # @return [Array<String>] Table names
    def tables
      query("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name").map { |row| row['name'] }
    end

    # Get column information for a table.
    #
    # @param table_name [String] Name of the table
    # @return [Array<Hash>] Column information
    def describe_table(table_name)
      raise ArgumentError, "Invalid table name: #{table_name}" unless valid_identifier?(table_name)

      query("PRAGMA table_info(#{table_name})")
    end

    # Get row count for a table.
    #
    # @param table_name [String] Name of the table
    # @return [Integer] Number of rows
    def count(table_name)
      raise ArgumentError, "Invalid table name: #{table_name}" unless valid_identifier?(table_name)

      query_single("SELECT COUNT(*) as count FROM #{table_name}")['count']
    end

    # Close the database connection.
    def close
      @connection&.close
      @connection = nil
    end

    private

    def connection
      @connection ||= open_readonly_connection
    end

    def open_readonly_connection
      # CRITICAL: Open in read-only mode
      db = SQLite3::Database.new(db_path.to_s, readonly: true)
      db.results_as_hash = true

      # Additional safety: set query_only pragma
      db.execute('PRAGMA query_only = ON')

      db
    end

    def validate_query!(sql)
      normalized = sql.upcase.strip

      FORBIDDEN_KEYWORDS.each do |keyword|
        next unless normalized.include?(keyword)

        raise ReadOnlyDatabaseError, "Modification queries are forbidden. Found: #{keyword}"
      end
    end

    def valid_identifier?(name)
      name.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/)
    end

    def row_to_hash(row)
      return row if row.is_a?(Hash)

      row.to_h
    end
  end
end
