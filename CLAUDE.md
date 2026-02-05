# Toggl Task Utility

## CRITICAL: Database Access Policy

**The Toggl database is STRICTLY READ-ONLY. No modifications allowed.**

### Enforcement Requirements

1. **Always open SQLite connections with `readonly: true`**:
   ```ruby
   require "sqlite3"
   db = SQLite3::Database.new(db_path, readonly: true)
   ```

2. **Never use INSERT, UPDATE, DELETE, DROP, ALTER, or CREATE statements**

3. **Use PRAGMA query_only for additional safety**:
   ```ruby
   db.execute("PRAGMA query_only = ON")
   ```

4. **All database interactions must be SELECT queries only**

## Finding the Toggl Database

The Toggl Track desktop app stores its SQLite database in platform-specific locations.

### Database Search Locations

**macOS:**
- `~/Library/Group Containers/*toggl*/production/` (auto-discovered via glob)
- `~/Library/Application Support/Toggl Track/`
- `~/Library/Application Support/Toggl Desktop/`

**Linux:**
- `~/.local/share/toggl/`
- `~/.config/Toggl Track/`

**Windows:**
- `%APPDATA%/Toggl Track/`
- `%APPDATA%/TogglDesktop/`

### Database Discovery

The utility should:
1. Search standard locations for `*.db` or `*.sqlite` files
2. Allow user to specify path via environment variable `TOGGL_DB_PATH`
3. Allow path override via command-line argument
4. Cache discovered path for subsequent runs

### Priority Order for Database Location

1. Command-line argument `--database, -d` (highest priority)
2. `TOGGL_DB_PATH` environment variable
3. Config file `database_path` setting
4. Auto-discovery from standard locations

## Code Guidelines

- Use a dedicated module for database access that enforces read-only
- All database queries should go through this module (`lib/toggl_db.rb`)
- Log all queries for debugging but never log sensitive data
- Handle database locked scenarios gracefully (Toggl may have it open)

## CLI Usage

### Setup

```bash
bundle install
```

### Commands

```bash
# Find the Toggl database
bin/toggl_db find

# List all tables
bin/toggl_db tables
bin/toggl_db tables --counts    # Include row counts

# Show table schema
bin/toggl_db schema time_entries

# Run a query
bin/toggl_db query "SELECT * FROM time_entries LIMIT 5"
bin/toggl_db query "SELECT * FROM projects" --format json
bin/toggl_db query "SELECT * FROM tasks" --format csv

# Sample rows from a table
bin/toggl_db sample time_entries
bin/toggl_db sample projects --limit 20

# Search for tables/columns
bin/toggl_db search project
bin/toggl_db search time

# Show search locations
bin/toggl_db locations

# Configuration management
bin/toggl_db config list                     # Show all settings
bin/toggl_db config get database_path        # Get a setting
bin/toggl_db config set database_path ~/db   # Set database path
bin/toggl_db config set default_format json  # Set default output format
bin/toggl_db config set default_limit 50     # Set default query limit
bin/toggl_db config path                     # Show config file location
bin/toggl_db config init                     # Create config with defaults
```

### Configuration

Config file location: `~/.config/toggl_db/config.yml`

Available settings:
- `database_path` - Path to Toggl database (default: auto-discover)
- `default_format` - Output format: table, json, csv (default: table)
- `default_limit` - Default row limit for queries (default: 100)

### Global Options

```bash
--database, -d PATH   # Specify database path explicitly
--format, -f FORMAT   # Output format: table, json, csv (default: table)
```

### Examples

```bash
# Use specific database
bin/toggl_db tables -d ~/my-toggl.db

# Export as JSON
bin/toggl_db query "SELECT * FROM projects" -f json > projects.json

# Export as CSV
bin/toggl_db sample time_entries -f csv > entries.csv
```

## Ruby API Usage

```ruby
require_relative "lib/toggl_db"

# Auto-discover database and query
db = TogglDb::Database.new
tasks = db.query("SELECT * FROM tasks WHERE active = 1")

# Or specify path explicitly
db = TogglDb::Database.new("/path/to/toggl.db")

# Quick one-off query
results = TogglDb.query("SELECT * FROM time_entries LIMIT 10")

# Find database location
path = TogglDb.find_database
puts "Database at: #{path}"

# List tables
db.tables.each { |t| puts t }

# Always close when done
db.close
```
