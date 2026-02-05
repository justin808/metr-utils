# toggl_db

A read-only CLI tool for exploring your local Toggl Track SQLite database and generating Metr TASK END reports.

## Features

- **Metr TASK END reports** - Generate productivity reports with AI usage breakdown
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

# Generate a Metr TASK END report
bin/toggl_db task-end

# Explore database tables
bin/toggl_db db tables
```

## Commands

### High-Level Commands

| Command | Description |
|---------|-------------|
| `task-end` | Generate a Metr TASK END report from today's entries |
| `find` | Find and display the Toggl database location |
| `config` | Manage configuration settings |
| `version` | Show version information |

### Database Exploration (`db` subcommand)

| Command | Description |
|---------|-------------|
| `db tables` | List all tables (use `--counts` for row counts) |
| `db schema TABLE` | Show column information for a table |
| `db query SQL` | Execute a read-only SQL query |
| `db sample TABLE` | Show sample rows from a table |
| `db search TERM` | Search for tables/columns by name |
| `db locations` | Show database search priority and paths |

## task-end Command

Generate Metr TASK END reports for productivity research:

```bash
# Show today's entries and pick which to report
bin/toggl_db task-end

# Specify time range
bin/toggl_db task-end --from "8:30am"

# Interactive mode for entering estimates
bin/toggl_db task-end --interactive
```

### Selection Interface

When multiple entries exist, you can:
- Select a single entry: `5`
- Select a range: `1-5`
- Select multiple: `1,3,5` or `1-3,5`
- Combine all: `A`
- Toggle sort by title: `T` (groups related tasks together)

### Task Description Metadata

Add estimates to your Toggl task descriptions using ` -- `:

```
Task name -- 30 min, 4 hours without
```

- First value (30 min) = With-AI estimate
- Second value (4 hours) = Without-AI estimate
- Use `-- continue` for continuation entries

### Output Example

```
============================================================
TASK END
Task: Metr Task Tracking using cowork
Clock: 11:46 AM - 03:01 PM
Focused time: 2.8hr
AI %: 33.2% (Claude 33.2%)
With-AI estimate: 30 min
Without-AI estimate: 4 hours
Quality: [1-5]
Notes: App breakdown - Claude: 33.2%, Conductor: 25.2%, Slack: 22.4%
============================================================
```

## Global Options

```bash
-d, --database PATH   # Specify database path explicitly
-f, --format FORMAT   # Output format: table, json, csv (default: table)
```

## Configuration

Store persistent settings in `~/.config/toggl_db/config.yml`:

```bash
# Set your database path once
bin/toggl_db config set database_path ~/path/to/toggl.db

# Set deploy target for bin/deploy
bin/toggl_db config set deploy_path ~/Documents/ClaudeCowork/Metr

# View all settings
bin/toggl_db config list
```

See `config.example.yml` for all available settings.

### Database Search Priority

1. `--database, -d` command-line option (highest)
2. `TOGGL_DB_PATH` environment variable
3. Config file `database_path` setting
4. Auto-discovery from standard locations

Run `bin/toggl_db db locations` to see all search paths and current values.

## Deployment

Deploy to a cloud folder or shared location:

```bash
# Deploy to a specific path and save it
bin/deploy /path/to/folder --save

# Subsequent deploys use saved path
bin/deploy
```

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
