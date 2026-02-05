# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'pathname'
require 'time'

module TogglDb
  # Persists task tracking data to JSON for Metr productivity research.
  # Tracks task IDs, task metadata, and associated snapshots.
  class TaskStore
    STORE_PATH = File.expand_path('~/.config/toggl_db/tasks.json')
    VERSION = 1

    class << self
      def instance
        @instance ||= new
      end

      def next_id
        instance.next_id
      end

      def create_task(attributes)
        instance.create_task(attributes)
      end

      def find_task(id)
        instance.find_task(id)
      end

      def current_task
        instance.current_task
      end

      def end_task(id, outcome_attributes)
        instance.end_task(id, outcome_attributes)
      end

      def add_snapshot(task_id, snapshot_data)
        instance.add_snapshot(task_id, snapshot_data)
      end

      def recent_tasks(limit = 10)
        instance.recent_tasks(limit)
      end

      def path
        instance.store_path
      end

      def reset_instance!
        @instance = nil
      end
    end

    attr_reader :store_path

    def initialize(path = nil)
      @store_path = Pathname.new(path || STORE_PATH)
      @data = load_data
    end

    def next_id
      @data['last_id'] + 1
    end

    def create_task(attributes)
      id = next_id
      @data['last_id'] = id
      @data['current_task_id'] = id

      task = {
        'id' => id,
        'description' => attributes[:description],
        'type' => attributes[:type],
        'use_ai' => attributes[:use_ai],
        'expected_time_minutes' => attributes[:expected_time_minutes],
        'without_ai_time_minutes' => attributes[:without_ai_time_minutes],
        'confidence' => attributes[:confidence],
        'why_ai' => attributes[:why_ai],
        'would_do_without_ai' => attributes[:would_do_without_ai],
        'started_at' => Time.now.iso8601,
        'ended_at' => nil,
        'outcome' => nil,
        'snapshots' => []
      }

      @data['tasks'] << task
      save
      task
    end

    def find_task(id)
      @data['tasks'].find { |t| t['id'] == id }
    end

    def current_task
      return nil unless @data['current_task_id']

      task = find_task(@data['current_task_id'])
      # Only return if task is still in progress (not ended)
      task && task['ended_at'].nil? ? task : nil
    end

    def end_task(id, outcome_attributes)
      task = find_task(id)
      return nil unless task

      task['ended_at'] = Time.now.iso8601
      task['outcome'] = outcome_attributes[:outcome]
      task['actual_elapsed_minutes'] = outcome_attributes[:actual_elapsed_minutes]
      task['active_work_minutes'] = outcome_attributes[:active_work_minutes]
      task['waiting_ai_minutes'] = outcome_attributes[:waiting_ai_minutes]
      task['ai_percentage'] = outcome_attributes[:ai_percentage]
      task['ai_turns'] = outcome_attributes[:ai_turns]
      task['final_without_ai_minutes'] = outcome_attributes[:without_ai_minutes]
      task['quality_vs_self'] = outcome_attributes[:quality_vs_self]
      task['notes'] = outcome_attributes[:notes]

      # Clear current task if it matches
      @data['current_task_id'] = nil if @data['current_task_id'] == id

      save
      task
    end

    def add_snapshot(task_id, snapshot_data)
      task = find_task(task_id)
      return nil unless task

      snapshot = {
        'time' => snapshot_data[:time]&.iso8601 || Time.now.iso8601,
        'ai_involved' => snapshot_data[:ai_involved],
        'focus' => snapshot_data[:focus],
        'same_task' => snapshot_data[:same_task],
        'ai_vanished_impact' => snapshot_data[:ai_vanished_impact],
        'what' => snapshot_data[:what],
        'type' => snapshot_data[:type]
      }

      task['snapshots'] << snapshot
      save
      snapshot
    end

    def recent_tasks(limit = 10)
      @data['tasks'].last(limit).reverse
    end

    def all_tasks
      @data['tasks']
    end

    def save
      FileUtils.mkdir_p(@store_path.dirname)
      File.write(@store_path, JSON.pretty_generate(@data))
    end

    def exists?
      @store_path.exist?
    end

    private

    def load_data
      if @store_path.exist?
        loaded = JSON.parse(File.read(@store_path))
        migrate_if_needed(loaded)
      else
        default_data
      end
    rescue JSON::ParserError
      default_data
    end

    def default_data
      {
        'version' => VERSION,
        'last_id' => 0,
        'current_task_id' => nil,
        'tasks' => []
      }
    end

    def migrate_if_needed(data)
      # Future migrations can be handled here based on version
      data['version'] ||= VERSION
      data['current_task_id'] ||= nil
      data['tasks'] ||= []
      data['last_id'] ||= 0
      data
    end
  end
end
