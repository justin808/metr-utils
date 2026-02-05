# toggl_db

A read-only CLI tool for exploring your local Toggl Track SQLite database.

## Features

- **Strictly read-only** - Multiple safety layers prevent any database modifications
- **Auto-discovery** - Automatically finds your Toggl database on macOS, Linux, and Windows
- **Flexible output** - Table, JSON, and CSV formats
- **Persistent config** - Save your database path and preferences

## Installation

```bash
git clone https://github.com/justin808/metr-utils.git
cd metr-utils
bundle install
```

## Quick Start

```bash
# Find your Toggl database
bin/toggl_db find

# List all tables
bin/toggl_db tables

# Sample data from a table
bin/toggl_db sample time_entries

# Run a query
bin/toggl_db query "SELECT * FROM projects LIMIT 10"
```

## Commands

| Command | Description |
|---------|-------------|
| `find` | Find and display the Toggl database location |
| `tables` | List all tables (use `--counts` for row counts) |
| `schema TABLE` | Show column information for a table |
| `query SQL` | Execute a read-only SQL query |
| `sample TABLE` | Show sample rows from a table |
| `search TERM` | Search for tables/columns by name |
| `locations` | Show database search priority and paths |
| `config` | Manage configuration settings |

### Global Options

```bash
-d, --database PATH   # Specify database path explicitly
-f, --format FORMAT   # Output format: table, json, csv (default: table)
```

### Examples

```bash
# Export projects as JSON
bin/toggl_db query "SELECT * FROM projects" -f json > projects.json

# Show time entries as CSV
bin/toggl_db sample time_entries -f csv

# Use a specific database file
bin/toggl_db tables -d ~/path/to/toggl.db

# Search for time-related tables and columns
bin/toggl_db search time
```

## Configuration

Store persistent settings in `~/.config/toggl_db/config.yml`:

```bash
# Set your database path once
bin/toggl_db config set database_path ~/Library/Application\ Support/Toggl\ Track/toggl.db

# View all settings
bin/toggl_db config list

# Available settings
bin/toggl_db config set default_format json    # Default output format
bin/toggl_db config set default_limit 50       # Default query row limit
```

### Database Search Priority

1. `--database, -d` command-line option (highest)
2. `TOGGL_DB_PATH` environment variable
3. Config file `database_path` setting
4. Auto-discovery from standard locations

Run `bin/toggl_db locations` to see all search paths and current values.

## Read-Only Safety

This tool enforces read-only access through multiple layers:

1. **SQLite read-only mode** - Connections opened with `readonly: true`
2. **PRAGMA query_only** - SQLite-level write protection
3. **Query validation** - Blocks INSERT, UPDATE, DELETE, DROP, ALTER, CREATE, etc.

Any attempt to modify data raises `TogglDb::ReadOnlyDatabaseError`.

## Ruby API

```ruby
require_relative 'lib/toggl_db'

# Auto-discover and connect
db = TogglDb::Database.new

# Or specify path
db = TogglDb::Database.new('/path/to/toggl.db')

# Query (SELECT only)
entries = db.query("SELECT * FROM time_entries LIMIT 10")

# Convenience methods
db.tables                    # List table names
db.describe_table('tasks')   # Column info
db.count('time_entries')     # Row count

db.close
```

## Database Locations

The tool searches these platform-specific locations:

**macOS:**
- `~/Library/Group Containers/*toggl*/production/` (auto-discovered)
- `~/Library/Application Support/Toggl Track/`
- `~/Library/Application Support/Toggl Desktop/`

**Linux:**
- `~/.local/share/toggl/`
- `~/.config/Toggl Track/`

**Windows:**
- `%APPDATA%/Toggl Track/`
- `%APPDATA%/TogglDesktop/`

## License

MIT
