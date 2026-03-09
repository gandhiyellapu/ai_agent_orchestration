# TD POC Automation

Automate Treasure Data POCs from raw data to customer segments using Claude AI.

## What This Does

This toolkit helps Solution Architects run POCs faster by automating:

1. **Init** - Clone templates, configure project
2. **Data Profiling** - Analyze raw data quality, detect PII, identify join keys, assess duplicates
3. **Staging** - Clean and standardize data (17 SQL patterns, auto-generated workflows)
4. **Post-Staging Analysis** - Detect table hierarchy, grain, join keys, unification readiness
5. **Unification** - Match customers across data sources
6. **Golden Layer** - Build single customer view
7. **Segments** - Create audience segments

## Requirements

- A MacBook (Intel or Apple Silicon)
- Treasure Data account with API access
- Internet connection

That's it. The setup script installs everything else.

---

## Quick Start (5 Minutes)

### Step 1: Clone the Repository

```bash
git clone https://github.com/your-org/ps_poc_automation.git
cd ps_poc_automation
```

### Step 2: Run Setup

```bash
./setup.sh
```

This installs:
- Homebrew (if needed)
- Node.js 22+ (required for TDX)
- Python 3.11
- Claude CLI
- TDX CLI (AI-native Treasure Data CLI)
- TD MCP Server
- TD Skills Plugin

### Step 3: Configure Your Environment

Copy the template and add your credentials:

```bash
cp .env.template .env
```

Edit `.env` with your favorite editor:

```bash
# Required - Get these from your TD account
TD_API_KEY=your-treasure-data-api-key
TD_SITE=us01                    # or eu01, ap02, etc.
TD_PROJECT_NAME=retail-poc      # Name for your workflows
TD_RAW_DB=raw_retail            # Database with your raw data
TD_STG_DB=stg_retail            # Database for cleaned data
```

### Step 4: Start Your POC

**Option A - Using TDX (recommended):**

```bash
tdx auth setup    # One-time: configure credentials
tdx claude        # Launches Claude with TD integration
```

**Option B - Using Claude directly:**

```bash
claude
```

Then type:

```
/poc-start
```

---

## Commands Reference

| Command | When to Use |
|---------|-------------|
| `/poc-start` | Starting a new POC |
| `/poc-profile` | Run data profiling only (without full POC pipeline) |
| `/poc-stage` | Run staging transformations only (after profiling) |
| `/poc-status` | Checking progress |
| `/poc-resume` | Continuing after a break |

---

## The Pipeline Explained

```
YOUR RAW DATA
     ↓
┌──────────────────────────────────────────────────┐
│ STEP 1: INIT                                     │
│ • Clone retail-poc-bp-ai template               │
│ • Configure project settings                    │
│ • Set up workflow directory structure            │
└──────────────────────────────────────────────────┘
     ↓
┌──────────────────────────────────────────────────┐
│ STEP 2: PROFILING                                │
│ • Scan all tables in parallel (3 at a time)     │
│ • Detect PII (email, phone, names, etc.)        │
│ • Identify join keys across tables              │
│ • Detect duplicates and identifier coverage     │
│ • Classify TD time column (event vs import)     │
│ • Assess JSON/ARRAY fields for staging          │
│ • Interactive approval of transformations       │
└──────────────────────────────────────────────────┘
     ↓
┌──────────────────────────────────────────────────┐
│ STEP 3: STAGING  (td-poc-staging skill)          │
│ • Apply 17 SQL patterns to clean data           │
│ • Standardize formats:                          │
│   - Emails → lowercase, validated               │
│   - Phones → digits only                        │
│   - Names → Title Case                          │
│   - Dates → 4 outputs (original, std, unix, date)│
│   - JSON → auto-extracted scalar fields         │
│ • Create trfmd_* columns with clean values      │
│ • Deploy + execute + monitor + validate          │
└──────────────────────────────────────────────────┘
     ↓
┌──────────────────────────────────────────────────┐
│ STEP 4: POST-STAGING ANALYSIS                    │
│ • Detect table hierarchy (parent/child)         │
│ • Analyze grain (one row per what?)             │
│ • Assess identity coverage across tables        │
│ • Generate unification readiness report         │
└──────────────────────────────────────────────────┘
     ↓
┌──────────────────────────────────────────────────┐
│ STEP 5: UNIFICATION                              │
│ • Match customers across tables                 │
│ • Link by email, phone, or customer ID          │
│ • Create unified customer IDs                   │
└──────────────────────────────────────────────────┘
     ↓
┌──────────────────────────────────────────────────┐
│ STEP 6: GOLDEN LAYER                             │
│ • Build one row per customer                    │
│ • Combine attributes from all sources           │
│ • Add derived metrics                           │
└──────────────────────────────────────────────────┘
     ↓
┌──────────────────────────────────────────────────┐
│ STEP 7: SEGMENTS                                 │
│ • Create audience segments                      │
│ • Ready for activation                          │
└──────────────────────────────────────────────────┘
     ↓
READY FOR CUSTOMER ACTIVATION
```

---

## Staging Transformations

Here's what happens to your data in the staging step:

| Data Type | What Happens | Example |
|-----------|--------------|---------|
| Email | Lowercase, validate, remove spaces | `" JOHN@GMAIL.COM "` → `john@gmail.com` |
| Phone | Keep digits only | `(555) 123-4567` → `5551234567` |
| Name | Title Case | `john doe` → `John Doe` |
| Date | 4 outputs: original, std, unix, date | `1990-05-15` → `642729600` + formatted |
| Yes/No | Standardize | `1`, `true` → `True` |
| Gender | Standardize | `f`, `female` → `Female` |
| Financial | Strip symbols, handle negatives | `($1,234.56)` → `-1234.56` |
| JSON | Auto-extract scalar fields | `{"name":"John"}` → `John` |
| Duplicates | Deduplicate via ROW_NUMBER | Keep latest row per key |

**Column naming**: Original columns stay. New `trfmd_` columns are added.

Example: `email` stays, `trfmd_email` is added with the clean version.

---

## Project Structure

```
ps_poc_automation/
├── .env.template          # Copy to .env and configure
├── setup.sh               # One-time setup script
├── CLAUDE.md              # AI instructions (read this!)
├── README.md              # You are here
├── .claude/
│   ├── commands/          # Slash commands (/poc-start, /poc-profile, etc.)
│   └── skills/
│       ├── td-poc/          # Master orchestrator + TD Platform Reference
│       ├── td-poc-staging/  # Staging SQL generation, testing, deployment
│       └── td-profiling/    # Data profiling skill (detection only)
├── tools/
│   ├── python/
│   │   └── state_manager.py   # Track POC progress
│   └── node/
│       └── watcher.js         # Monitor TD workflows
├── .poc-state/            # Created when you start a POC
│   ├── current-poc.json   # Current progress
│   ├── profiling-report.md      # Human-readable profiling summary
│   ├── profiling-choices.json   # User-approved transformation choices
│   └── profiles/                # Per-table JSON profiles
│       ├── customers.json
│       └── orders.json
└── reference/
    └── retail-poc-bp-ai/   # Template workflows
```

---

## Troubleshooting

### "TD_API_KEY not set"

Edit your `.env` file and add your Treasure Data API key:

```bash
TD_API_KEY=1234/abcdefghijklmnop
```

Get your API key from: TD Console → User Settings → API Keys

### "Database not found"

Make sure your raw database exists and you have access:

```bash
td db:list
```

Update `TD_RAW_DB` in `.env` to match an existing database.

### "Command not found: claude"

Run the setup script again:

```bash
./setup.sh
```

Then start a new terminal or run:

```bash
source ~/.zshrc
```

### POC stuck

Check the status:

```
/poc-status
```

If a workflow is failing, check TD workflow logs for details.

---

## Background Monitoring

For long-running workflows, use the watcher:

```bash
# Run in background
node tools/node/watcher.js --daemon

# Check once and exit
node tools/node/watcher.js --once
```

The watcher:
- Checks TD session status every 60 seconds
- Auto-retries failed workflows (up to 10 times)
- Sends Slack notifications (if configured)

---

## Configuration Options

All settings go in `.env`:

| Setting | Default | Description |
|---------|---------|-------------|
| `TD_API_KEY` | (required) | Your Treasure Data API key |
| `TD_SITE` | `us01` | TD region (us01, eu01, ap02, etc.) |
| `TD_PROJECT_NAME` | (required) | Name for your TD workflow project |
| `TD_RAW_DB` | (required) | Database with raw data |
| `TD_STG_DB` | (required) | Database for staging tables |
| `MAX_RETRIES` | `10` | How many times to retry failed workflows |
| `DEBUG_MODE` | `true` | Use 10% data sample for testing |
| `SLACK_WEBHOOK_URL` | (none) | Slack webhook for notifications |

---

## FAQ

### How long does a POC take?

Depends on data size:
- Small (< 1M rows): 1-2 hours
- Medium (1-10M rows): 2-4 hours
- Large (> 10M rows): 4-8 hours

### Can I pause and resume?

Yes! Close your laptop anytime. When you return:

```
/poc-resume
```

### What if something fails?

The system automatically retries up to 10 times. If it still fails, you'll get a notification and can fix the issue manually.

### Where are my results?

- Staging tables: In your `TD_STG_DB` database
- Progress: `.poc-state/current-poc.json`
- Logs: `.poc-state/errors.log`

---

## Getting Help

1. Check `/poc-status` for current state
2. Read `CLAUDE.md` for detailed documentation
3. Check TD workflow logs for errors
4. Ask in #ps-automation Slack channel

---

## Contributing

Found a bug or want to add a feature?

1. Create a branch
2. Make your changes
3. Test with a small dataset
4. Submit a PR

---

## License

Internal use only. Property of Treasure Data.
