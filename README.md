# toggl_db

A read-only CLI tool for exploring your local Toggl Track SQLite database and generating Metr productivity research reports.

## Features

- **Metr productivity reports** - Generate TASK START, TASK END, and SNAPSHOT reports
- **Strictly read-only** - Multiple safety layers prevent any database modifications
- **Auto-discovery** - Automatically finds your Toggl database on macOS, Linux, and Windows
- **Flexible output** - Default (human-friendly) or strict Metr format
- **Task tracking** - Local bookkeeping for Metr Task IDs and metadata
- **Persistent config** - Save your database path and preferences

## How Task Tracking Works

**Important:** The `task-start` command creates a local record for Metr reporting purposes - it does **not** start a timer in the Toggl app.

The workflow is:

1. **Start your Toggl timer** manually in the Toggl app
2. **Run `task-start`** to record Metr metadata (Task ID, AI intent, time estimates)
3. **Work on your task**, optionally running `snapshot` periodically
4. **Run `task-end`** to generate the Metr report (reads your Toggl time entries)

The "tracking" is bookkeeping for Metr's required fields that Toggl doesn't capture:
- Auto-incrementing Task IDs
- Pre-task AI usage intent and time estimates
- Confidence levels and task types
- Periodic snapshots of work status

Task data is stored locally in `~/.config/toggl_db/tasks.json`.

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

# Typical Metr workflow:
# 1. Start your Toggl timer in the Toggl app
# 2. Record Metr task metadata
bin/toggl_db task-start

# 3. Periodically record snapshots (optional)
bin/toggl_db snapshot

# 4. When done, generate the TASK END report
bin/toggl_db task-end --format metr

# Check task status anytime
bin/toggl_db status

# Explore database tables
bin/toggl_db db tables
```

## Commands

### Metr Productivity Commands

| Command | Description |
|---------|-------------|
| `task-start` | Start a new Metr task (records metadata, does NOT start Toggl timer) |
| `task-end` | Generate a Metr TASK END report from Toggl time entries |
| `snapshot` | Record a point-in-time work status snapshot |
| `status` | Show current task and recent task history |

### Utility Commands

| Command | Description |
|---------|-------------|
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

## task-start Command

Begin a new Metr task by recording metadata locally. This does **not** start a Toggl timer - you should start your Toggl timer separately.

```bash
# Interactive mode - prompts for all fields
bin/toggl_db task-start

# Output in strict Metr format
bin/toggl_db task-start --format metr

# Write output to file
bin/toggl_db task-start -o ~/tasks.txt
```

The command prompts for:
- Task description
- Whether you'll use AI (Yes/No)
- Expected time with AI (minutes)
- Without-AI estimate (minutes)
- Confidence level (1-5)
- Why you're using AI (if applicable)
- Whether you would do this without AI
- Task type (Code, Debug, Research, Write, Meet, Plan, Break, Other)

### Output Example (Metr format)

```
=== TASK START ===
Task ID: 1
Time: 2024-01-15 09:30
Description: Implement user authentication

1. WILL USE AI? Yes
2. EXPECTED TIME: 30 min
3. WITHOUT AI WOULD TAKE: 120 min
4. CONFIDENCE (1-5): 3
5. WHY AI? Complex logic, good for pair programming
6. WOULD DO WITHOUT AI? Yes
7. TYPE: Code
```

## task-end Command

Generate Metr TASK END reports from your Toggl time entries:

```bash
# Show today's entries and pick which to report
bin/toggl_db task-end

# Specify time range
bin/toggl_db task-end --from "8:30am"

# Interactive mode - prompts for all Metr fields
bin/toggl_db task-end --interactive

# Strict Metr format output
bin/toggl_db task-end --format metr

# Write output to file
bin/toggl_db task-end -o ~/report.txt
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

### Output Example (default format)

```
============================================================
TASK END
Task: Metr Task Tracking using cowork
Clock: 2024-01-15 11:46 AM - 03:01 PM
Focused time: 2.8hr
AI %: 33.2% (Claude 33.2%)
With-AI estimate: 30 min
Without-AI estimate: 4 hours
Quality: [1-5]
Notes: App breakdown - Claude: 33.2%, Conductor: 25.2%, Slack: 22.4%
============================================================
```

### Output Example (Metr format with `--format metr`)

```
=== TASK END ===
Task ID: 1
Time: 2024-01-15 15:01

1. USED AI? Yes
2. TOTAL ELAPSED: 168 min
3. TIME BREAKDOWN:
   Active work: 150 min
   Waiting/reviewing AI: 18 min
4. OUTCOME: Completed
5. IF USED AI:
   % from AI: 33.2
   # of AI turns: 25
6. WITHOUT AI WOULD TAKE: 240 min
7. IF USED AI - QUALITY vs yourself: Slightly better
8. NOTES: Claude: 33.2%, Conductor: 25.2%, Slack: 22.4%
```

## snapshot Command

Record a point-in-time snapshot of your current work status:

```bash
# Interactive snapshot
bin/toggl_db snapshot

# Strict Metr format
bin/toggl_db snapshot --format metr

# Append to file (useful for multiple snapshots)
bin/toggl_db snapshot -o ~/snapshots.txt --append

# Link to a specific task
bin/toggl_db snapshot --task-id 3
```

The command prompts for:
- AI involvement (No, Yes-waiting, Yes-actively using, Yes-using output)
- Focus level (Fully on one thing, Switching, Distracted)
- Same task as last snapshot (Yes, No, Don't know)
- If AI vanished impact (Unaffected, Somewhat longer, Much longer, Blocked)
- What you're doing (one line)
- Task type

### Output Example (Metr format)

```
=== SNAPSHOT ===
Time: 2024-01-15 10:45

1. AI INVOLVED? Yes-actively using
2. FOCUS: Fully on one thing
3. SAME TASK AS LAST SNAPSHOT? Yes
4. IF AI VANISHED: Somewhat longer
5. WHAT: Writing authentication middleware
   Type: Code
```

## status Command

Show current task and recent history:

```bash
bin/toggl_db status
bin/toggl_db status --limit 10
```

Output:
```
Current Task:
  #3: Implement user authentication
  Type: Code
  Started: 2024-01-15T09:00:00Z
  AI: Yes
  Snapshots: 2

Recent Tasks (last 5):
  #3: Implement user authentication [active]
  #2: Fix login bug [done]
  #1: Setup project [done]

Task store: /Users/you/.config/toggl_db/tasks.json
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
