# frozen_string_literal: true

require 'yaml'
require 'pathname'
require 'fileutils'

module TogglDb
  class Config
    DEFAULT_CONFIG_PATH = File.expand_path('~/.config/toggl_db/config.yml')

    DEFAULTS = {
      'database_path' => nil,        # Path to Toggl database (nil = auto-discover)
      'default_format' => 'table',   # Output format: table, json, csv
      'default_limit' => 100         # Default row limit for queries
    }.freeze

    class << self
      def load(path = nil)
        @instance = new(path)
      end

      def instance
        @instance ||= new
      end

      def [](key)
        instance[key]
      end

      def []=(key, value)
        instance[key] = value
      end

      def save
        instance.save
      end

      def path
        instance.config_path
      end

      def exists?
        instance.exists?
      end

      def to_h
        instance.to_h
      end
    end

    attr_reader :config_path

    def initialize(path = nil)
      @config_path = Pathname.new(path || DEFAULT_CONFIG_PATH)
      @data = load_config
    end

    def [](key)
      @data[key.to_s]
    end

    def []=(key, value)
      @data[key.to_s] = value
    end

    def to_h
      @data.dup
    end

    def save
      FileUtils.mkdir_p(@config_path.dirname)
      File.write(@config_path, @data.to_yaml)
    end

    def reset!
      @data = DEFAULTS.dup
      save
    end

    def exists?
      @config_path.exist?
    end

    private

    def load_config
      if @config_path.exist?
        loaded = YAML.safe_load_file(@config_path) || {}
        DEFAULTS.merge(loaded)
      else
        DEFAULTS.dup
      end
    end
  end
end
