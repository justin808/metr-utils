# frozen_string_literal: true

require 'thor'
require 'json'
require_relative '../toggl_db'
require_relative 'cli/db_commands'
require_relative 'cli/metr_formatter'
require_relative 'cli/task_end_command'
require_relative 'cli/task_start_command'
require_relative 'cli/snapshot_command'
require_relative 'task_store'

module TogglDb
  class CLI < Thor
    class_option :database, aliases: '-d', type: :string,
                            desc: 'Path to Toggl database (default: auto-discover)'

    def self.exit_on_failure?
      true
    end

    # Remove the built-in tree command (shows confusing internal naming)
    remove_command :tree

    # Register the db subcommand for advanced database exploration
    desc 'db SUBCOMMAND', 'Database exploration commands (advanced)'
    subcommand 'db', DbCommands

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

    desc 'version', 'Show version information'
    def version
      say 'toggl_db 0.2.0'
      say 'Read-only Toggl database explorer with Metr task reporting'
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

    desc 'status', 'Show current task status and recent tasks'
    long_desc <<~DESC
      Shows the current in-progress task (if any) and recent task history.

      Example:
        $ toggl_db status
    DESC
    option :limit, aliases: '-l', type: :numeric, default: 5,
                   desc: 'Number of recent tasks to show'
    def status
      say ''
      display_current_task
      say ''
      display_recent_tasks
      say ''
      say "Task store: #{TaskStore.path}", :cyan
    end

    private

    def display_current_task
      current = TaskStore.current_task
      if current
        say 'Current Task:', :green
        say "  ##{current['id']}: #{current['description']}"
        say "  Type: #{current['type']}"
        say "  Started: #{current['started_at']}"
        say "  AI: #{current['use_ai'] ? 'Yes' : 'No'}"
        snapshots = current['snapshots']&.length || 0
        say "  Snapshots: #{snapshots}"
      else
        say 'No task in progress.', :yellow
        say "Use 'toggl_db task-start' to begin a new task."
      end
    end

    def display_recent_tasks
      recent = TaskStore.recent_tasks(options[:limit])
      if recent.any?
        say "Recent Tasks (last #{options[:limit]}):", :green
        recent.each do |task|
          status_indicator = task['ended_at'] ? 'done' : 'active'
          say "  ##{task['id']}: #{task['description']} [#{status_indicator}]"
        end
      else
        say 'No tasks recorded yet.', :yellow
      end
    end

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
