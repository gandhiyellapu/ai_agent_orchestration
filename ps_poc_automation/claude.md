# Super Claude Kit Integration

This project uses **Super Claude Kit** - a persistent context memory system for Claude Code that enables cross-message and cross-session memory.

## 📋 Requirements

- **Git**: Required for capsule and session tracking
- **Python 3**: Required for manifest parsing and hooks
- **Go 1.20+**: Required for building dependency tools (optional but recommended)
  - `dependency-scanner`: Analyze code dependencies and relationships
  - `progressive-reader`: Read large files efficiently with tree-sitter parsing
  - Install from: https://go.dev/dl/

**Note**: The kit works without Go, but dependency analysis tools will not be available.

## 🎯 System Overview

Super Claude Kit provides:
- **Persistent Context**: Remember files accessed, tasks worked on, and discoveries made
- **Smart Refresh**: Automatic context updates before each prompt
- **Cross-Session Memory**: Context persists across sessions (24-hour window)
- **Sub-Agent Tracking**: Remember findings from specialized agents
- **Discovery Logging**: Capture architectural insights and patterns

## 📖 Usage Guide

**CRITICAL**: Read and follow `.claude/docs/CAPSULE_USAGE_GUIDE.md`

## 🔒 Production Safety

Super Claude Kit is designed for safe production use:

**Sub-Agents (Read-Only):**
All 4 built-in sub-agents (architecture-explorer, database-navigator, agent-developer, github-issue-tracker) are **read-only**. They can analyze and explore code but cannot modify files or execute destructive operations.

**✅ Sub-agents CAN:**
- Read files (Read tool)
- Search code (Grep tool)
- Find files (Glob tool)
- Fetch web content (WebFetch - architecture-explorer only)

**❌ Sub-agents CANNOT:**
- Execute bash commands (Bash tool removed)
- Modify files (no Edit/Write tools)
- Delete files or run destructive operations

This design prevents accidental file modifications while maintaining full analytical capabilities.

### Required Behavior

Claude (you!) MUST follow these patterns:

#### 1. Check Capsule Before Redundant Operations
```
BEFORE re-reading a file → Check if it's in capsule (Files in Context)
BEFORE running git status → Check capsule (Git State)
BEFORE asking about current task → Check capsule (Current Tasks)
```

#### 2. Logging (Mostly Automatic)

**AUTO-LOGGED (PostToolUse Hook):**
The following are logged automatically - you don't need to call these manually:
- Read/Edit/Write operations → Logged to session_files.log automatically
- Task tool (sub-agents) → Logged to session_subagents.log automatically
- TodoWrite updates → Logged to session_tasks.log automatically

**MANUAL LOGGING REQUIRED (Discoveries Only):**
You must manually log discoveries - you decide what's important:

```bash
./.claude/hooks/log-discovery.sh "<category>" "<insight>"
# Categories: pattern, insight, decision, architecture, bug, optimization, achievement

# Examples:
./.claude/hooks/log-discovery.sh "pattern" "All hooks use set -euo pipefail"
./.claude/hooks/log-discovery.sh "architecture" "System uses microservices"
./.claude/hooks/log-discovery.sh "decision" "Using PostgreSQL for storage"
```

**OPTIONAL MANUAL LOGGING:**
Only needed if PostToolUse hook is disabled:

```bash
# File access (automatic via PostToolUse)
./.claude/hooks/log-file-access.sh "<path>" "read|edit|write"

# Sub-agents (automatic via PostToolUse)
./.claude/hooks/log-subagent.sh "<agent-type>" "<summary-of-findings>"

# Tasks (automatic via TodoWrite + PostToolUse)
./.claude/hooks/log-task.sh "<status>" "<task-description>"
```

#### 3. Workflow Pattern

```
1. Check capsule → See current context
2. Start task → Use TodoWrite (auto-logged)
3. Work on task → Read/edit files (auto-logged)
4. Use sub-agents → Task tool (auto-logged)
5. Log discoveries → Manual logging (you decide what's important)
6. Complete task → Mark as completed (auto-logged via TodoWrite)
```

**Auto-logging coverage: ~95%**
Only discoveries require manual logging - everything else is automatic!

## ⚡ Tool Enforcement Rules

<tool-enforcement-rules priority="critical">
  <description>
    Super Claude Kit provides specialized tools that are FASTER and MORE ACCURATE than generic exploration.
    These rules are MANDATORY and enforced by PreToolUse hook.
  </description>

  <dependency-analysis category="always-use">
    <query type="what imports this file">
      <command>bash .claude/tools/query-deps/query-deps.sh &lt;file-path&gt;</command>
      <use-case>Finding files that import/depend on a specific file</use-case>
    </query>

    <query type="who uses this function">
      <command>bash .claude/tools/query-deps/query-deps.sh &lt;file-path&gt;</command>
      <use-case>Checking if a function/export is used before deleting</use-case>
    </query>

    <query type="what depends on X">
      <command>bash .claude/tools/query-deps/query-deps.sh &lt;file-path&gt;</command>
      <use-case>Understanding dependency relationships</use-case>
    </query>

    <query type="what would break if I change X">
      <command>bash .claude/tools/impact-analysis/impact-analysis.sh &lt;file-path&gt;</command>
      <use-case>Impact analysis before refactoring</use-case>
      <returns>Direct dependents, transitive dependents, risk assessment</returns>
    </query>

    <query type="circular dependencies">
      <command>bash .claude/tools/find-circular/find-circular.sh</command>
      <use-case>Finding import cycles</use-case>
      <returns>All circular dependency chains with fix suggestions</returns>
    </query>

    <query type="dead code">
      <command>bash .claude/tools/find-dead-code/find-dead-code.sh</command>
      <use-case>Finding unused/unreferenced files</use-case>
      <returns>List of potentially unused files</returns>
    </query>

    <never-use tool="Task" subagent="Explore" reason="inefficient-and-incomplete">
      <reason priority="high">Slower - must read and parse files sequentially</reason>
      <reason priority="high">Incomplete - may miss indirect dependencies</reason>
      <reason priority="high">Expensive - high token usage for simple queries</reason>
      <reason priority="critical">Cannot detect circular dependencies</reason>
    </never-use>
  </dependency-analysis>

  <file-search category="always-use">
    <tool name="Glob" reason="direct-file-matching">
      <query type="find file by name">
        <pattern>**/*auth*</pattern>
        <use-case>Where is the auth file?</use-case>
      </query>

      <query type="find files by extension">
        <pattern>**/*.ts</pattern>
        <use-case>Find all TypeScript files</use-case>
      </query>
    </tool>

    <never-use tool="Task" subagent="Explore" reason="inefficient">
      <alternative>Use Glob tool for direct file name/pattern matching</alternative>
    </never-use>
  </file-search>

  <code-search category="always-use">
    <tool name="Grep" reason="fast-pattern-matching">
      <query type="find by keyword">
        <pattern>TODO</pattern>
        <use-case>Find all TODO comments</use-case>
      </query>

      <query type="find definition">
        <pattern>function X</pattern>
        <use-case>Where is function X defined?</use-case>
      </query>
    </tool>

    <never-use tool="Task" subagent="Explore" reason="inefficient">
      <alternative>Use Grep tool for code pattern searches</alternative>
    </never-use>
  </code-search>

  <large-file-navigation category="use-for-structure" threshold="50KB">
    <tool name="progressive-reader" reason="file-navigation-and-structure-discovery">
      <description>
        Progressive-reader is a NAVIGATION TOOL for large files. Use it to understand
        file structure BEFORE reading, then read only what you need.
      </description>

      <primary-value feature="--list">
        The --list command shows file structure WITHOUT reading content:
        - Shows all functions/classes with their chunk numbers
        - Each chunk has a summary of what it contains
        - ~500 tokens to see entire file structure (vs ~48,000 for full read)
        - BETTER THAN GREP for understanding "what's in this file?"
      </primary-value>

      <workflow>
        <step1>Discover structure: .claude/bin/progressive-reader --path &lt;file&gt; --list</step1>
        <step2>Find relevant chunks from function/class names in the list</step2>
        <step3>Read specific chunk: .claude/bin/progressive-reader --path &lt;file&gt; --chunk N</step3>
        <step4>Continue if needed: .claude/bin/progressive-reader --continue-file /tmp/continue.toon</step4>
      </workflow>

      <when-to-use>
        <case>Understanding file structure - "What functions are in this file?"</case>
        <case>Finding specific functionality - "Which part handles authentication?"</case>
        <case>Adding new code - "Show me similar functions so I can follow the pattern"</case>
        <case>Targeted reading - "I need to understand just the login function"</case>
        <case>Context-limited sessions - nearing token limits, need efficient reading</case>
      </when-to-use>

      <when-grep-is-fine>
        <case>Finding specific keyword occurrences</case>
        <case>Searching for error messages or strings</case>
        <case>Quick lookups where you know what you're searching for</case>
      </when-grep-is-fine>

      <languages>TypeScript, JavaScript, Python, Go (full AST parsing)</languages>
      <fallback>Other languages use line-based chunking (still useful, less intelligent)</fallback>
      <token-savings>75-97% vs full file read</token-savings>
    </tool>

    <guidance for="Read-tool">
      <use-read-when>File is under 50KB OR you genuinely need the entire file</use-read-when>
      <use-progressive-when>File is large AND you need structure/specific sections</use-progressive-when>
      <note>PreToolUse hook will warn if you try to Read a file over 50KB</note>
    </guidance>

    <mandatory-file-size-check priority="CRITICAL">
      <rule>BEFORE using Read tool, ALWAYS check file size first:</rule>
      <check>Run: wc -c &lt;file&gt; | awk '{print int($1/1024)"KB"}'</check>

      <decision>
        <if-under-50KB>Use Read tool normally</if-under-50KB>
        <if-over-50KB>STOP. Use progressive-reader instead:</if-over-50KB>
      </decision>

      <progressive-reader-command>
        <list>.claude/bin/progressive-reader --path &lt;file&gt; --list</list>
        <read-chunk>.claude/bin/progressive-reader --path &lt;file&gt; --chunk N</read-chunk>
      </progressive-reader-command>

      <why-this-matters>
        Files over 50KB (~12,500+ tokens) cause MaxFileReadTokenExceededError.
        Each failed Read attempt wastes tokens. Check size FIRST.
      </why-this-matters>
    </mandatory-file-size-check>

    <error-recovery priority="CRITICAL">
      <trigger>MaxFileReadTokenExceededError</trigger>
      <action>IMMEDIATELY stop using Read tool on this file</action>
      <solution>Switch to: .claude/bin/progressive-reader --path &lt;file&gt; --list</solution>
      <do-not>Do NOT retry Read with offset/limit - use progressive-reader</do-not>
    </error-recovery>
  </large-file-navigation>

  <task-tool-allowed-uses>
    <allowed priority="high">
      <use-case>Complex architectural questions requiring analysis</use-case>
      <example>How does the authentication system work?</example>
    </allowed>

    <allowed priority="high">
      <use-case>Implementation understanding</use-case>
      <example>How does X work internally?</example>
    </allowed>

    <allowed priority="medium">
      <use-case>Multi-file refactoring planning</use-case>
      <example>Plan refactoring of auth module across files</example>
    </allowed>

    <allowed priority="medium">
      <use-case>Design pattern identification</use-case>
      <example>What patterns are used in this codebase?</example>
    </allowed>

    <not-allowed>
      <forbidden>Dependency lookups - use query-deps instead</forbidden>
      <forbidden>File searches - use Glob instead</forbidden>
      <forbidden>Code searches - use Grep instead</forbidden>
    </not-allowed>
  </task-tool-allowed-uses>

  <enforcement-mechanism>
    <hook name="PreToolUse" action="intercept-and-warn">
      PreToolUse hook intercepts Task tool calls for dependency queries and displays enforcement warnings.
      READ THESE WARNINGS - they indicate you are using the wrong tool.
    </hook>

    <required>true</required>
    <bypass>not-allowed</bypass>
  </enforcement-mechanism>
</tool-enforcement-rules>

## Best Practices

<best-practices priority="critical">
  <required-behaviors>
    <behavior priority="high">Check capsule before redundant file reads</behavior>
    <behavior priority="medium">Capture sub-agent findings immediately</behavior>
    <behavior priority="medium">Note architectural discoveries as you learn</behavior>
    <behavior priority="high">Reference capsule context in responses</behavior>
  </required-behaviors>

  <forbidden-behaviors>
    <forbidden priority="critical">Ignore the capsule (defeats the purpose!)</forbidden>
    <forbidden priority="high">Re-read files shown in capsule (unless stale)</forbidden>
    <forbidden priority="medium">Launch duplicate sub-agents for same task</forbidden>
  </forbidden-behaviors>
</best-practices>

## Available Dependency Tools

<dependency-tools>
  <tool name="query-deps">
    <command>./.claude/tools/query-deps.sh &lt;file-path&gt;</command>
    <when-to-use>Before deleting files, understanding dependencies</when-to-use>
  </tool>

  <tool name="impact-analysis">
    <command>./.claude/tools/impact-analysis.sh &lt;file-path&gt;</command>
    <when-to-use>Before refactoring, assessing change risk</when-to-use>
  </tool>

  <tool name="find-circular">
    <command>./.claude/tools/find-circular.sh</command>
    <when-to-use>Debugging import failures, finding cycles</when-to-use>
  </tool>

  <tool name="find-dead-code">
    <command>./.claude/tools/find-dead-code.sh</command>
    <when-to-use>Code cleanup, finding unused files</when-to-use>
  </tool>
</dependency-tools>

---

# TD POC Enabler

This project automates Treasure Data POC workflows for Solution Architects.

## Session Startup

**IMPORTANT**: At the start of every session, read the `.env` file to load project configuration. This file contains critical values like `TD_RAW_DB`, `TD_STG_DB`, `TD_PROJECT_NAME`, and other POC settings that most commands and workflows depend on. Do this before any POC-related work.

## Quick Start Commands

| Command | What it does |
|---------|--------------|
| `/poc-start` | Start a new POC |
| `/poc-profile` | Run data profiling only |
| `/poc-status` | Check current progress |
| `/poc-resume` | Continue after a break |

## The Pipeline (What Happens Step by Step)

```
Step 1: INIT                  → Set up project, copy templates
Step 2: PROFILING             → Profile data quality, detect PII
Step 3: STAGING               → Clean and standardize data (see below!)
Step 4: POST-STAGING ANALYSIS → Hierarchy, grain, join key analysis on clean data
Step 5: UNIFICATION           → Match customers across tables
Step 6: GOLDEN                → Build one row per customer
Step 7: SEGMENT               → Create audience segments
```

---

## STAGING EXPLAINED (Like You're 15)

### What is Staging?

Staging takes your messy raw data and makes it clean and consistent. Think of it like cleaning your room - everything gets organized the same way.

### What Transformations Happen?

Here's what we do to each type of data:

#### EMAIL ADDRESSES
- **What we do**: Remove weird characters, make lowercase
- **Example**: `"  JOHN@Gmail.COM  "` becomes `"john@gmail.com"`
- **Original column**: `email`
- **New column**: `trfmd_email` (trfmd = transformed)

#### PHONE NUMBERS
- **What we do**: Keep only digits, remove spaces/dashes/parentheses
- **Example**: `"(555) 123-4567"` becomes `"5551234567"`
- **Original column**: `phone` or `phone_number`
- **New column**: `trfmd_phone`

#### NAMES (First Name, Last Name)
- **What we do**: Title Case (first letter capital), remove extra spaces
- **Example**: `"  JOHN DOE  "` becomes `"John Doe"`
- **Original columns**: `first_name`, `last_name`
- **New columns**: `trfmd_first_name`, `trfmd_last_name`

#### DATES (Birthday, Sign-up Date)
- **What we do**: Convert to Unix timestamp (seconds since 1970)
- **Example**: `"1990-05-15"` becomes `642729600`
- **Why**: Makes date math easy across all systems
- **Original column**: `date_of_birth`
- **New column**: `trfmd_dob_unix`

#### YES/NO VALUES (Consent, Opt-in)
- **What we do**: Standardize to `"True"` or `"False"`
- **Example**: `"1"`, `"true"`, `"yes"` all become `"True"`
- **Example**: `"0"`, `"false"`, `"no"` all become `"False"`
- **Original column**: `consent_flag`
- **New column**: `trfmd_consent_flag`

#### IDs (Customer ID, Account ID)
- **What we do**: Make uppercase, ensure consistent type
- **Example**: `"abc123"` becomes `"ABC123"`
- **Original column**: `customer_id`
- **New column**: `trfmd_customer_id`

### Column Naming Convention

| Original | Transformed | What Happened |
|----------|-------------|---------------|
| `email` | `trfmd_email` | Cleaned, lowercased |
| `phone` | `trfmd_phone` | Digits only |
| `first_name` | `trfmd_first_name` | Title Case |
| `last_name` | `trfmd_last_name` | Title Case |
| `date_of_birth` | `trfmd_dob_unix` | Unix timestamp |
| `consent_flag` | `trfmd_consent_flag` | True/False |
| `customer_id` | `trfmd_customer_id` | Uppercase |

### Important Notes

- **Original columns are kept!** We add new `trfmd_` columns, we don't replace
- **NULL handling**: Empty strings, "null", whitespace all become actual NULL
- **PII detection**: Columns that look like personal info get flagged for review

---

## Tools Reference

### State Manager (Python)

```bash
# Check status
python3 tools/python/state_manager.py status

# Start new POC
python3 tools/python/state_manager.py start "my-poc" --raw-db "raw_db" --stg-db "stg_db"

# Move to next stage
python3 tools/python/state_manager.py stage staging

# Mark stage done
python3 tools/python/state_manager.py complete staging

# Record a failure
python3 tools/python/state_manager.py fail staging "Column not found"

# Track TD workflow session
python3 tools/python/state_manager.py session 12345 --workflow wf03

# Get resume point after break
python3 tools/python/state_manager.py resume
```

### Background Watcher (Node.js)

```bash
# Watch TD sessions (foreground)
node tools/node/watcher.js

# Single check
node tools/node/watcher.js --once

# Run in background
node tools/node/watcher.js --daemon
```

The watcher:
- Polls TD every 60 seconds for session status
- Retries failed workflows (up to 10 times by default)
- Sends Slack notifications if configured
- Updates `.poc-state/current-poc.json`

---

## TD MCP Tools

Use TD MCP for all database operations:

```
list_databases    - See all databases
list_tables       - See tables in a database
describe_table    - Get column names and types
query             - Run SQL queries
list_sessions     - Check running workflows
get_task_logs     - Debug failed workflows
```

---

## State Files

```
.poc-state/
├── current-poc.json          ← Current progress
├── config.json               ← POC settings
├── profiling-report.md       ← Human-readable profiling summary
├── profiling-choices.json    ← User-approved transformation choices
├── profiles/                 ← Per-table JSON profiles
│   ├── customers.json
│   └── orders.json
└── errors.log                ← What went wrong
```

---

## Error Handling

### Automatic Retry

When a TD workflow fails:
1. Watcher detects failure
2. Waits 5 minutes
3. Retries automatically
4. Repeats up to 10 times
5. If still failing → Slack alert for help

### Common Errors and Fixes

| Error | Likely Cause | Fix |
|-------|--------------|-----|
| Column not found | Typo in SQL | Check column name in schema |
| Type mismatch | Wrong CAST | Add CAST(col AS VARCHAR) |
| Table not found | Wrong database | Check TD_RAW_DB in .env |
| Session timeout | Long-running query | Increase timeout or optimize SQL |

---

## Configuration (.env)

```bash
# Required
TD_API_KEY=your-api-key      # Never share this!
TD_SITE=us01                 # Your TD region
TD_PROJECT_NAME=retail-poc   # Workflow project name
TD_RAW_DB=raw_retail         # Source database
TD_STG_DB=stg_retail         # Target database

# Optional
MAX_RETRIES=10               # Retry attempts per stage
POLL_INTERVAL_SECONDS=60     # How often to check status
RETRY_DELAY_SECONDS=300      # Wait between retries (5 min)
SLACK_WEBHOOK_URL=           # For notifications
DEBUG_MODE=true              # Use 10% data samples
```

---

## Best Practices

### DO
- Always test SQL with LIMIT 100 first
- Update state after each operation
- Get human approval for config changes
- Keep raw data READ-ONLY

### DON'T
- Hardcode credentials
- Skip the profiling step
- Run full data without debug test
- Ignore PII detection warnings

### Shell Alias Compatibility

Some users alias standard commands to modern alternatives (`grep` → `rg`, `find` → `fd`). These have different flag syntax and will break if called with standard flags.

**Rules for Claude:**
- **Prefer built-in tools**: Use `Grep` tool (not `bash grep`) and `Glob` tool (not `bash find`) — these bypass shell aliases entirely
- **When bash is unavoidable**: Use `command grep` / `command find` to bypass aliases
- **Never assume** standard GNU flags work — the user's shell may remap them

---

## Troubleshooting

### POC won't start
1. Check `.env` file exists
2. Verify `TD_API_KEY` is valid: `td db:list`
3. Make sure databases exist

### Workflow stuck
1. Check watcher: `pgrep -f watcher.js`
2. Check TD session: `/poc-status`
3. Get logs: Use TD MCP `get_task_logs`

### Can't resume
1. Check `.poc-state/current-poc.json` exists
2. Run `python3 tools/python/state_manager.py status`
3. If corrupted, may need to reset

---

## Reference Files

```
reference/retail-poc-bp-ai/
├── wf00_orchestration.dig              ← Master orchestrator
├── wf01_run_workflow_with_logging.dig  ← Step runner with logging
├── wf02_mapping.dig                    ← Column mapping (removed during staging)
├── wf03_validate.dig                   ← Validation checks
├── wf04_stage.dig                      ← Staging workflow
├── wf05_unify.dig                      ← Identity resolution
├── wf06_golden.dig                     ← Golden layer build
├── wf07_analytics.dig                  ← Analytics dashboard
├── wf08_create_refresh_master_segment.dig  ← Master segment
├── wf09_create_segment.dig             ← Segment creation
├── config/                             ← YAML configs (src_params, schema_map, email_ids)
└── staging/queries/                    ← SQL templates (regenerated per POC)
```


---

# Claude Capsule Kit Integration

This project uses **Claude Capsule Kit** - a persistent context memory system for Claude Code that enables cross-message and cross-session memory.

## 📋 Requirements

- **Git**: Required for capsule and session tracking
- **Python 3**: Required for manifest parsing and hooks
- **Go 1.20+**: Required for building dependency tools (optional but recommended)
  - `dependency-scanner`: Analyze code dependencies and relationships
  - `progressive-reader`: Read large files efficiently with tree-sitter parsing
  - Install from: https://go.dev/dl/

**Note**: The kit works without Go, but dependency analysis tools will not be available.

## 🎯 System Overview

Claude Capsule Kit provides:
- **Persistent Context**: Remember files accessed, tasks worked on, and discoveries made
- **Smart Refresh**: Automatic context updates before each prompt
- **Cross-Session Memory**: Context persists across sessions (24-hour window)
- **Sub-Agent Tracking**: Remember findings from specialized agents
- **Discovery Logging**: Capture architectural insights and patterns

## 📖 Usage Guide

**CRITICAL**: Read and follow `.claude/docs/CAPSULE_USAGE_GUIDE.md`

## 🔒 Production Safety

Claude Capsule Kit is designed for safe production use:

**Sub-Agents (Read-Only):**
All 4 built-in sub-agents (architecture-explorer, database-navigator, agent-developer, github-issue-tracker) are **read-only**. They can analyze and explore code but cannot modify files or execute destructive operations.

**✅ Sub-agents CAN:**
- Read files (Read tool)
- Search code (Grep tool)
- Find files (Glob tool)
- Fetch web content (WebFetch - architecture-explorer only)

**❌ Sub-agents CANNOT:**
- Execute bash commands (Bash tool removed)
- Modify files (no Edit/Write tools)
- Delete files or run destructive operations

This design prevents accidental file modifications while maintaining full analytical capabilities.

### Required Behavior

Claude (you!) MUST follow these patterns:

#### 1. Check Capsule Before Redundant Operations
```
BEFORE re-reading a file → Check if it's in capsule (Files in Context)
BEFORE running git status → Check capsule (Git State)
BEFORE asking about current task → Check capsule (Current Tasks)
```

#### 2. Logging (Mostly Automatic)

**AUTO-LOGGED (PostToolUse Hook):**
The following are logged automatically - you don't need to call these manually:
- Read/Edit/Write operations → Logged to session_files.log automatically
- Task tool (sub-agents) → Logged to session_subagents.log automatically
- TodoWrite updates → Logged to session_tasks.log automatically

**MANUAL LOGGING REQUIRED (Discoveries Only):**
You must manually log discoveries - you decide what's important:

```bash
./.claude/hooks/log-discovery.sh "<category>" "<insight>"
# Categories: pattern, insight, decision, architecture, bug, optimization, achievement

# Examples:
./.claude/hooks/log-discovery.sh "pattern" "All hooks use set -euo pipefail"
./.claude/hooks/log-discovery.sh "architecture" "System uses microservices"
./.claude/hooks/log-discovery.sh "decision" "Using PostgreSQL for storage"
```

**OPTIONAL MANUAL LOGGING:**
Only needed if PostToolUse hook is disabled:

```bash
# File access (automatic via PostToolUse)
./.claude/hooks/log-file-access.sh "<path>" "read|edit|write"

# Sub-agents (automatic via PostToolUse)
./.claude/hooks/log-subagent.sh "<agent-type>" "<summary-of-findings>"

# Tasks (automatic via TodoWrite + PostToolUse)
./.claude/hooks/log-task.sh "<status>" "<task-description>"
```

#### 3. Workflow Pattern

```
1. Check capsule → See current context
2. Start task → Use TodoWrite (auto-logged)
3. Work on task → Read/edit files (auto-logged)
4. Use sub-agents → Task tool (auto-logged)
5. Log discoveries → Manual logging (you decide what's important)
6. Complete task → Mark as completed (auto-logged via TodoWrite)
```

**Auto-logging coverage: ~95%**
Only discoveries require manual logging - everything else is automatic!

## ⚡ Tool Enforcement Rules

<tool-enforcement-rules priority="critical">
  <description>
    Claude Capsule Kit provides specialized tools that are FASTER and MORE ACCURATE than generic exploration.
    These rules are MANDATORY and enforced by PreToolUse hook.
  </description>

  <dependency-analysis category="always-use">
    <query type="what imports this file">
      <command>bash .claude/tools/query-deps/query-deps.sh &lt;file-path&gt;</command>
      <use-case>Finding files that import/depend on a specific file</use-case>
    </query>

    <query type="who uses this function">
      <command>bash .claude/tools/query-deps/query-deps.sh &lt;file-path&gt;</command>
      <use-case>Checking if a function/export is used before deleting</use-case>
    </query>

    <query type="what depends on X">
      <command>bash .claude/tools/query-deps/query-deps.sh &lt;file-path&gt;</command>
      <use-case>Understanding dependency relationships</use-case>
    </query>

    <query type="what would break if I change X">
      <command>bash .claude/tools/impact-analysis/impact-analysis.sh &lt;file-path&gt;</command>
      <use-case>Impact analysis before refactoring</use-case>
      <returns>Direct dependents, transitive dependents, risk assessment</returns>
    </query>

    <query type="circular dependencies">
      <command>bash .claude/tools/find-circular/find-circular.sh</command>
      <use-case>Finding import cycles</use-case>
      <returns>All circular dependency chains with fix suggestions</returns>
    </query>

    <query type="dead code">
      <command>bash .claude/tools/find-dead-code/find-dead-code.sh</command>
      <use-case>Finding unused/unreferenced files</use-case>
      <returns>List of potentially unused files</returns>
    </query>

    <never-use tool="Task" subagent="Explore" reason="inefficient-and-incomplete">
      <reason priority="high">Slower - must read and parse files sequentially</reason>
      <reason priority="high">Incomplete - may miss indirect dependencies</reason>
      <reason priority="high">Expensive - high token usage for simple queries</reason>
      <reason priority="critical">Cannot detect circular dependencies</reason>
    </never-use>
  </dependency-analysis>

  <file-search category="always-use">
    <tool name="Glob" reason="direct-file-matching">
      <query type="find file by name">
        <pattern>**/*auth*</pattern>
        <use-case>Where is the auth file?</use-case>
      </query>

      <query type="find files by extension">
        <pattern>**/*.ts</pattern>
        <use-case>Find all TypeScript files</use-case>
      </query>
    </tool>

    <never-use tool="Task" subagent="Explore" reason="inefficient">
      <alternative>Use Glob tool for direct file name/pattern matching</alternative>
    </never-use>
  </file-search>

  <code-search category="always-use">
    <tool name="Grep" reason="fast-pattern-matching">
      <query type="find by keyword">
        <pattern>TODO</pattern>
        <use-case>Find all TODO comments</use-case>
      </query>

      <query type="find definition">
        <pattern>function X</pattern>
        <use-case>Where is function X defined?</use-case>
      </query>
    </tool>

    <never-use tool="Task" subagent="Explore" reason="inefficient">
      <alternative>Use Grep tool for code pattern searches</alternative>
    </never-use>
  </code-search>

  <large-file-navigation category="use-for-structure" threshold="50KB">
    <tool name="progressive-reader" reason="file-navigation-and-structure-discovery">
      <description>
        Progressive-reader is a NAVIGATION TOOL for large files. Use it to understand
        file structure BEFORE reading, then read only what you need.
      </description>

      <primary-value feature="--list">
        The --list command shows file structure WITHOUT reading content:
        - Shows all functions/classes with their chunk numbers
        - Each chunk has a summary of what it contains
        - ~500 tokens to see entire file structure (vs ~48,000 for full read)
        - BETTER THAN GREP for understanding "what's in this file?"
      </primary-value>

      <workflow>
        <step1>Discover structure: .claude/bin/progressive-reader --path &lt;file&gt; --list</step1>
        <step2>Find relevant chunks from function/class names in the list</step2>
        <step3>Read specific chunk: .claude/bin/progressive-reader --path &lt;file&gt; --chunk N</step3>
        <step4>Continue if needed: .claude/bin/progressive-reader --continue-file /tmp/continue.toon</step4>
      </workflow>

      <when-to-use>
        <case>Understanding file structure - "What functions are in this file?"</case>
        <case>Finding specific functionality - "Which part handles authentication?"</case>
        <case>Adding new code - "Show me similar functions so I can follow the pattern"</case>
        <case>Targeted reading - "I need to understand just the login function"</case>
        <case>Context-limited sessions - nearing token limits, need efficient reading</case>
      </when-to-use>

      <when-grep-is-fine>
        <case>Finding specific keyword occurrences</case>
        <case>Searching for error messages or strings</case>
        <case>Quick lookups where you know what you're searching for</case>
      </when-grep-is-fine>

      <languages>TypeScript, JavaScript, Python, Go (full AST parsing)</languages>
      <fallback>Other languages use line-based chunking (still useful, less intelligent)</fallback>
      <token-savings>75-97% vs full file read</token-savings>
    </tool>

    <guidance for="Read-tool">
      <use-read-when>File is under 50KB OR you genuinely need the entire file</use-read-when>
      <use-progressive-when>File is large AND you need structure/specific sections</use-progressive-when>
      <note>PreToolUse hook will warn if you try to Read a file over 50KB</note>
    </guidance>

    <mandatory-file-size-check priority="CRITICAL">
      <rule>BEFORE using Read tool, ALWAYS check file size first:</rule>
      <check>Run: wc -c &lt;file&gt; | awk '{print int($1/1024)"KB"}'</check>

      <decision>
        <if-under-50KB>Use Read tool normally</if-under-50KB>
        <if-over-50KB>STOP. Use progressive-reader instead:</if-over-50KB>
      </decision>

      <progressive-reader-command>
        <list>.claude/bin/progressive-reader --path &lt;file&gt; --list</list>
        <read-chunk>.claude/bin/progressive-reader --path &lt;file&gt; --chunk N</read-chunk>
      </progressive-reader-command>

      <why-this-matters>
        Files over 50KB (~12,500+ tokens) cause MaxFileReadTokenExceededError.
        Each failed Read attempt wastes tokens. Check size FIRST.
      </why-this-matters>
    </mandatory-file-size-check>

    <error-recovery priority="CRITICAL">
      <trigger>MaxFileReadTokenExceededError</trigger>
      <action>IMMEDIATELY stop using Read tool on this file</action>
      <solution>Switch to: .claude/bin/progressive-reader --path &lt;file&gt; --list</solution>
      <do-not>Do NOT retry Read with offset/limit - use progressive-reader</do-not>
    </error-recovery>
  </large-file-navigation>

  <task-tool-allowed-uses>
    <allowed priority="high">
      <use-case>Complex architectural questions requiring analysis</use-case>
      <example>How does the authentication system work?</example>
    </allowed>

    <allowed priority="high">
      <use-case>Implementation understanding</use-case>
      <example>How does X work internally?</example>
    </allowed>

    <allowed priority="medium">
      <use-case>Multi-file refactoring planning</use-case>
      <example>Plan refactoring of auth module across files</example>
    </allowed>

    <allowed priority="medium">
      <use-case>Design pattern identification</use-case>
      <example>What patterns are used in this codebase?</example>
    </allowed>

    <not-allowed>
      <forbidden>Dependency lookups - use query-deps instead</forbidden>
      <forbidden>File searches - use Glob instead</forbidden>
      <forbidden>Code searches - use Grep instead</forbidden>
    </not-allowed>
  </task-tool-allowed-uses>

  <enforcement-mechanism>
    <hook name="PreToolUse" action="intercept-and-warn">
      PreToolUse hook intercepts Task tool calls for dependency queries and displays enforcement warnings.
      READ THESE WARNINGS - they indicate you are using the wrong tool.
    </hook>

    <required>true</required>
    <bypass>not-allowed</bypass>
  </enforcement-mechanism>
</tool-enforcement-rules>

## Best Practices

<best-practices priority="critical">
  <required-behaviors>
    <behavior priority="high">Check capsule before redundant file reads</behavior>
    <behavior priority="medium">Capture sub-agent findings immediately</behavior>
    <behavior priority="medium">Note architectural discoveries as you learn</behavior>
    <behavior priority="high">Reference capsule context in responses</behavior>
  </required-behaviors>

  <forbidden-behaviors>
    <forbidden priority="critical">Ignore the capsule (defeats the purpose!)</forbidden>
    <forbidden priority="high">Re-read files shown in capsule (unless stale)</forbidden>
    <forbidden priority="medium">Launch duplicate sub-agents for same task</forbidden>
  </forbidden-behaviors>
</best-practices>

## Available Dependency Tools

<dependency-tools>
  <tool name="query-deps">
    <command>./.claude/tools/query-deps.sh &lt;file-path&gt;</command>
    <when-to-use>Before deleting files, understanding dependencies</when-to-use>
  </tool>

  <tool name="impact-analysis">
    <command>./.claude/tools/impact-analysis.sh &lt;file-path&gt;</command>
    <when-to-use>Before refactoring, assessing change risk</when-to-use>
  </tool>

  <tool name="find-circular">
    <command>./.claude/tools/find-circular.sh</command>
    <when-to-use>Debugging import failures, finding cycles</when-to-use>
  </tool>

  <tool name="find-dead-code">
    <command>./.claude/tools/find-dead-code.sh</command>
    <when-to-use>Code cleanup, finding unused files</when-to-use>
  </tool>
</dependency-tools>
