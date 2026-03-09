# TD CDP Pipeline Setup - Master Orchestration Guide

## Overview

This is the **master orchestration skill** that guides you through setting up a complete Treasure Data CDP pipeline from scratch.

**Pipeline Flow:**
```
profiling → staging → unification → golden → segmentation
   (0)        (1)         (2)         (3)         (4)

Optional: idu_dashboard (after unification), analytics (after golden)
```

**Duration:** 4-8 hours (depending on data size)
**Prerequisites:** TD account, API access, TDX CLI installed

---

## Step 0: Environment Setup & Prerequisites

### 0.1: Run Setup Script (if not already done)

```bash
cd ps_poc_automation
./setup.sh
```

This installs:
- Homebrew (if needed)
- Node.js 22+
- Python 3.11
- Claude CLI
- TDX CLI
- TD MCP Server

### 0.2: Gather Requirements from User

**Ask the user these questions:**

1. **Client/Subscriber name** (used as `sub` prefix)
   - Example: `acme_retail`
   - Used for: Database naming (`stg_acme_retail`, `gldn_acme_retail`)

2. **Project name** (used for TD workflow project)
   - Example: `acme-retail-cdp`
   - Used for: Workflow project name in TD Console

3. **Source database name** (existing TD database with raw data)
   - Example: `raw_acme_retail`
   - Must exist in TD account

4. **Unification ID name** (the unified customer identifier)
   - Example: `canonical_id`, `td_unified_id`, `master_id`
   - Recommended: `canonical_id`

5. **IDU Dashboard** (optional quality dashboard)
   - Ask: "Do you want to include IDU (ID Unification) dashboard for quality monitoring?"
   - Options: yes/no
   - If no: Skip step 6 entirely

6. **Analytics Dashboard** (optional business intelligence)
   - Ask: "Do you want to include analytics dashboards (sales, web, etc.)?"
   - Options: yes/no
   - If no: Skip step 8 entirely

7. **Dashboard user emails** (for access grants)
   - Example: `['user@company.com', 'analyst@company.com']`
   - Used for: Dashboard sharing

8. **Notification emails** (for workflow alerts)
   - Example: `['ops@company.com']`
   - Used for: Success/error notifications

9. **Scheduling** (when to run the pipeline)
   - Options:
     - Off (manual runs only)
     - Daily at 4 AM ET
     - Custom cron schedule
   - Example: `cron>: "0 4 * * *"` (daily 4 AM UTC)

### 0.3: Create Project Structure

```bash
# Create project directory
mkdir -p <sub>_workflow
cd <sub>_workflow

# Copy workflow template
cp -r ../workflow-skills/workflow-template/* .

# Create working directories
mkdir -p .poc-state/profiles
mkdir -p staging/queries
mkdir -p golden/queries/attributes
mkdir -p unification
mkdir -p segment/config/parent_segment_templates
```

### 0.4: Initialize Configuration

Create `config/src_params.yml`:

```yaml
# Project configuration
sub: <client_name>
project_name: <project_name>

# Source configuration
source_database: <source_database_name>

# Target databases
src: <source_database_name>
stg: stg
gld: gldn
analytics: analytics

# TD Configuration
site: us01  # or eu01, ap02, etc.

# Unification configuration
unification_id: <unification_id_name>

# Workflow configuration
run_all: false  # Set to true to force re-run all steps

# Segment configuration
segment:
  run_type: "create"
  tables:
    parent_segment_templates: ps_templates
    parent_segment_creation: ps_creation_log
    active_audience: active_audiences

# Notification emails
notification_emails:
  - <email1>
  - <email2>

# Dashboard user emails
dashboard_users:
  - <email1>
  - <email2>
```

---

## Step 1: Data Profiling (Discovery & Analysis)

**Skill:** `profiling_skill.md`

**Goal:** Understand source data structure, detect PII, identify join keys, assess quality.

### 1.1: Execute Profiling

Run through `profiling_skill.md`:
- List all tables in source database
- Get schema for each table
- Run data quality queries (null rates, duplicates)
- Detect PII (email, phone, name, dates)
- Identify join keys across tables
- Classify time columns (event vs import)
- Assess JSON/ARRAY fields

### 1.2: Review Profiling Report

Present `profiling-report.md` to user:
```
📊 Profiling Results:

Source Database: <database>
Tables Found: <count>
Total Rows: <count>

Tables with Customer Data:
- customers: <row_count> rows, PII detected: email, phone, name
- orders: <row_count> rows, PII detected: customer_email
- consents: <row_count> rows, PII detected: email, phone
- pageviews: <row_count> rows, PII detected: user_email

Recommended Transformations:
- <N> email columns → trfmd_email
- <N> phone columns → trfmd_phone
- <N> name columns → trfmd_first_name, trfmd_last_name
- <N> date columns → trfmd_*_unix

Recommended Join Keys:
1. customer_id (coverage: <pct>%)
2. email (coverage: <pct>%)
3. phone (coverage: <pct>%)

Ready to proceed to staging? (yes/no)
```

### 1.3: User Approval

Get user confirmation:
- Review profiling findings
- Approve transformations
- Confirm tables to include in staging
- Approve unification keys

Store approved choices in `profiling-choices.json`.

### 1.4: Checkpoint

✅ Profiling complete
- [ ] profiling-report.md created
- [ ] profiling-choices.json created
- [ ] User approved transformations
- [ ] Ready for staging

---

## Step 2: Staging (Data Cleaning)

**Skill:** `staging_skill.md`

**Goal:** Create clean staging tables with standardized `trfmd_*` columns.

### 2.1: Generate Staging SQL Queries

Run through `staging_skill.md`:
- Read `profiling-choices.json`
- Generate staging SQL for each table
- Apply transformations (email, phone, name, date, etc.)
- Create `staging/queries/<table>.sql` for each table
- Create `staging/queries/invalid_emails.sql` for quality checks

### 2.2: Update Workflow Files

- Update `wf2_stage.dig` with table list
- Update `config/src_params.yml` with staging tables

### 2.3: Push to TD Console

```bash
cd <sub>_workflow

# Push workflow
tdx wf push <project_name>

# Verify upload
tdx wf list <project_name> | grep staging
```

**Get user confirmation:**
```
Ready to push staging workflow to TD Console?
Tables to stage: <list>
Target database: stg_<sub>

Push? (yes/no)
```

### 2.4: Run Staging Workflow

```bash
# Run staging
tdx wf run <project_name> wf2_stage

# Monitor
SESSION_ID=<returned_id>
tdx wf session <SESSION_ID>
```

Monitor status every 30 seconds until success or error.

### 2.5: Handle Errors (if any)

If workflow fails:
1. Get error message from logs
2. Identify failing table/query
3. Fix `staging/queries/<table>.sql`
4. Push updated workflow
5. Re-run workflow
6. Repeat until success

### 2.6: Validate Results

```bash
# Check staging tables created
tdx tables stg_<sub>

# Check row counts
tdx query "SELECT COUNT(*) FROM stg_<sub>.customers"

# Verify transformations
tdx query "SELECT email, trfmd_email, trfmd_email_status FROM stg_<sub>.customers LIMIT 10"
```

### 2.7: Generate Staging Report

Present `staging-report.md` to user:
```
✓ Staging Complete!

Staging Database: stg_<sub>
Tables Created: <count>
Total Rows: <count>

Tables:
- customers: <rows>, transformations: email, phone, name
- orders: <rows>, transformations: email
- consents: <rows>, transformations: email, phone

Email Quality: <valid_pct>% valid
Phone Quality: <valid_pct>% valid

Ready to proceed to unification? (yes/no)
```

### 2.8: Checkpoint

✅ Staging complete
- [ ] All staging tables created in `stg_<sub>`
- [ ] Transformations validated
- [ ] staging-report.md created
- [ ] User confirmed ready for unification

---

## Step 3: Unification (Identity Resolution)

**Skill:** `unification_skill.md`

**Goal:** Match customer records across tables to create unified customer IDs.

### 3.1: Configure Unification

Run through `unification_skill.md`:
- Analyze unification strategy
- Define primary/secondary keys
- Configure `unification/unify.yml`
- Set match rules
- Define survivorship rules

### 3.2: Add TD API Key Secret

```bash
# Add API key as secret
td wf secret set <project_name> td.apikey

# Enter API key when prompted
# Format: <account_id>/<api_key>
```

### 3.3: Push to TD Console

```bash
# Push unification workflow
tdx wf push <project_name>

# Verify
tdx wf list <project_name> | grep unif
```

**Get user confirmation:**
```
Ready to run unification?
Unification ID: <unification_id>
Match rules: customer_id (exact), email (exact), phone (exact)
Expected duration: 30 min - 2 hours

Run unification? (yes/no)
```

### 3.4: Run Unification Workflow

```bash
# Run unification
tdx wf run <project_name> wf3_unify

# Monitor (check every 2 minutes)
SESSION_ID=<returned_id>
tdx wf session <SESSION_ID>
```

This is a long-running process. Monitor until completion.

### 3.5: Handle Errors (if any)

If workflow fails:
1. Get error from session logs
2. Fix `unification/unify.yml`
3. Push updated workflow
4. Re-run
5. Repeat until success

### 3.6: Validate Unification Results

```bash
# Check unification database
tdx tables cdp_unif_<sub>

# Check unified customer count
tdx query "SELECT COUNT(DISTINCT ${unification_id}) FROM cdp_unif_<sub>.${unification_id}_master"

# Check coverage
tdx query "
SELECT
  source_table,
  COUNT(*) as records,
  COUNT(${unification_id}) as unified,
  ROUND(100.0 * COUNT(${unification_id}) / COUNT(*), 2) as coverage_pct
FROM cdp_unif_<sub>.${unification_id}_lookup
GROUP BY 1
"

# Check for over-merging
tdx query "
SELECT
  ${unification_id},
  COUNT(DISTINCT source_id) as num_merged
FROM cdp_unif_<sub>.${unification_id}_lookup
GROUP BY 1
HAVING COUNT(DISTINCT source_id) > 20
LIMIT 10
"
```

### 3.7: Generate Unification Report

Present `unification-report.md` to user:
```
✓ Unification Complete!

Unified Customers: <count>
Unification Coverage: <pct>%
Average Merge Rate: <avg> source IDs per customer

Match Statistics:
- customer_id matches: <pct>%
- email matches: <pct>%
- phone matches: <pct>%

Quality Check:
- Over-merging: <status>
- Coverage: <status>

Ready to proceed to golden layer? (yes/no)
```

### 3.8: Checkpoint

✅ Unification complete
- [ ] Unification database created: `cdp_unif_<sub>`
- [ ] Master table exists: `${unification_id}_master`
- [ ] Coverage validated (>95%)
- [ ] No critical over-merging detected
- [ ] unification-report.md created
- [ ] User confirmed ready for golden

---

## Step 4: Golden Layer (Single Customer View)

**Skill:** `golden_skill.md`

**Goal:** Create unified golden database with master identity + attributes + behaviors.

### 4.1: Generate Golden SQL Queries

Run through `golden_skill.md`:
- Create `golden/queries/all_profile_identifiers.sql`
- Create `golden/queries/copy_enriched_table.sql`
- Create row-level table queries (orders, consents, etc.)
- Create attribute table queries (transactions, email_activity, pageviews, etc.)

### 4.2: Update Workflow

Update `wf5_golden.dig` with table lists.

### 4.3: Push to TD Console

```bash
# Push golden workflow
tdx wf push <project_name>

# Verify
tdx wf list <project_name> | grep golden
```

**Get user confirmation:**
```
Ready to build golden layer?
Master table: profile_identifiers
Attributes: transactions, email_activity, pageviews, etc.
Behaviors: orders, consents, etc.
Target database: gldn_<sub>

Build golden layer? (yes/no)
```

### 4.4: Run Golden Workflow

```bash
# Run golden
tdx wf run <project_name> wf5_golden

# Monitor
SESSION_ID=<returned_id>
tdx wf session <SESSION_ID>
```

### 4.5: Handle Errors (if any)

If workflow fails:
1. Get error from logs
2. Fix golden SQL queries
3. Push updated workflow
4. Re-run
5. Repeat until success

### 4.6: Validate Golden Results

```bash
# Check golden tables
tdx tables gldn_<sub>

# Check master identity count
tdx query "SELECT COUNT(*) FROM gldn_<sub>.profile_identifiers"

# Check attribute tables
tdx query "SELECT COUNT(*) FROM gldn_<sub>.attr_transactions"

# Verify data
tdx query "
SELECT
  p.${unification_id},
  p.trfmd_email,
  t.total_orders,
  t.lifetime_revenue
FROM gldn_<sub>.profile_identifiers p
LEFT JOIN gldn_<sub>.attr_transactions t USING (${unification_id})
LIMIT 10
"
```

### 4.7: Generate Golden Report

Present `golden-report.md` to user:
```
✓ Golden Layer Complete!

Golden Database: gldn_<sub>
Total Customers: <count>

Tables Created:
- profile_identifiers: <count> customers
- attr_transactions: <count> customers (<pct>% coverage)
- attr_email_activity: <count> customers (<pct>% coverage)
- attr_pageviews: <count> customers (<pct>% coverage)
- orders: <count> rows
- consents: <count> rows

Ready to proceed to segmentation? (yes/no)
```

### 4.8: Checkpoint

✅ Golden layer complete
- [ ] Golden database created: `gldn_<sub>`
- [ ] Master identity table: `profile_identifiers`
- [ ] All attribute tables created
- [ ] All row-level tables created
- [ ] golden-report.md created
- [ ] User confirmed ready for segmentation

---

## Step 5: Segmentation (Parent Segment)

**Skill:** `segmentation_skill.md`

**Goal:** Create parent segment for audience building and activation.

### 5.1: Configure Parent Segment

Run through `segmentation_skill.md`:
- Read golden table schemas
- Configure `segment/config/parent_segment_templates/retail_parent_segment_template.yml`
- Map attributes (identity, demographics, purchase, engagement, web)
- Map behaviors (orders, consents, etc.)
- Validate configuration

### 5.2: Push to TD Console

```bash
# Push segment workflow
tdx wf push <project_name>

# Verify
tdx wf list <project_name> | grep segment
```

**Get user confirmation:**
```
Ready to create parent segment?
Master table: gldn_<sub>.profile_identifiers
Attributes: <count>
Behaviors: <count>

Create parent segment? (yes/no)
```

### 5.3: Run Segmentation Workflow

```bash
# Run segmentation
tdx wf run <project_name> wf7_segment

# Monitor
SESSION_ID=<returned_id>
tdx wf session <SESSION_ID>
```

### 5.4: Handle Errors (if any)

If workflow fails:
1. Get error from logs
2. Fix parent segment YAML
3. Push updated workflow
4. Re-run
5. Repeat until success

### 5.5: Verify Parent Segment

```bash
# List parent segments
tdx ps list

# Get details
tdx ps get <parent_segment_id>

# Preview data
tdx ps preview <parent_segment_id> --limit 100
```

### 5.6: Create Test Segments

```bash
# Test segment: High-value customers
tdx sg create \
  --parent-segment <parent_segment_id> \
  --name "High Value Customers" \
  --filter "lifetime_revenue > 1000"

# Test segment: Recent purchasers
tdx sg create \
  --parent-segment <parent_segment_id> \
  --name "Recent Purchasers" \
  --filter "days_since_last_purchase < 30"
```

### 5.7: Generate Segmentation Report

Present `segmentation-report.md` to user:
```
✓ Segmentation Complete!

Parent Segment ID: <parent_segment_id>
Total Profiles: <count>
Attributes: <count>
Behaviors: <count>

Test Segments Created:
- High Value Customers: <count>
- Recent Purchasers: <count>

Your CDP pipeline is complete! ✅
```

### 5.8: Checkpoint

✅ Segmentation complete
- [ ] Parent segment created
- [ ] Test segments validated
- [ ] segmentation-report.md created
- [ ] Pipeline is fully operational

---

## Step 6: Final Validation & Handoff

### 6.1: Run End-to-End Test

If orchestration workflow exists:

```bash
# Run full pipeline
tdx wf run <project_name> wf00_orchestration

# Monitor entire flow
SESSION_ID=<returned_id>
tdx wf session <SESSION_ID>
```

Monitor all steps:
1. Database creation
2. Staging
3. Unification
4. Golden
5. Segmentation

### 6.2: Generate Final Summary

Create `pipeline-summary.md`:

```markdown
# CDP Pipeline Summary - <project_name>

## Configuration
- Client: <sub>
- Project: <project_name>
- Source Database: <source_database>
- Unification ID: ${unification_id}

## Pipeline Status: ✅ COMPLETE

### Databases Created
- `stg_<sub>` - Staging (clean data)
- `cdp_unif_<sub>` - Unification (unified IDs)
- `gldn_<sub>` - Golden (single customer view)

### Data Summary
- Total Customers: <count>
- Staging Tables: <count>
- Golden Attribute Tables: <count>
- Golden Behavior Tables: <count>
- Parent Segment Attributes: <count>
- Parent Segment Behaviors: <count>

### Parent Segment
- ID: <parent_segment_id>
- Profiles: <count>
- Ready for activation: ✅

## Next Steps
1. Create custom audience segments in TD Console
2. Activate segments to marketing channels
3. Build customer journeys
4. Monitor and optimize

## Resources
- Profiling Report: `profiling-report.md`
- Staging Report: `staging-report.md`
- Unification Report: `unification-report.md`
- Golden Report: `golden-report.md`
- Segmentation Report: `segmentation-report.md`
```

### 6.3: User Handoff

Present final message:
```
🎉 Your Treasure Data CDP Pipeline is successfully deployed and running!

Pipeline Summary:
- Customers: <count>
- Databases: stg_<sub>, cdp_unif_<sub>, gldn_<sub>
- Parent Segment: <parent_segment_id>
- Test Segments: 2 created

What you can do now:
1. Create audience segments in TD Console
2. Activate segments to Facebook, Google Ads, etc.
3. Build customer journeys
4. Run analytics on your unified data

Documentation:
- Full pipeline summary: pipeline-summary.md
- All reports saved in .poc-state/

Need help?
- TD Console: https://console.treasuredata.com
- Documentation: https://docs.treasuredata.com
- Support: support@treasuredata.com

Thank you for using TD CDP Pipeline Automation! ✅
```

---

## Error Recovery

If any step fails:
1. **Don't panic** - Errors are normal, especially first runs
2. **Get logs** - Use `tdx wf session <SESSION_ID>` and check task logs
3. **Identify root cause** - Find the specific failing query or config
4. **Fix the issue** - Update SQL, YAML, or workflow file
5. **Push updates** - `tdx wf push <project_name>`
6. **Re-run** - `tdx wf run <project_name> <workflow>`
7. **Repeat** - Keep iterating until success

Common issues:
- Column not found → Check table schema
- Data type mismatch → Add CAST
- Table not found → Verify previous step completed
- API auth failed → Add secret
- Timeout → Reduce data size or optimize query

---

## Helper Skills Reference

Use these skills for each pipeline step:

| Step | Skill | Purpose |
|------|-------|---------|
| 0 | `profiling_skill.md` | Data discovery, PII detection, quality assessment |
| 1 | `staging_skill.md` | Data cleaning, transformation |
| 2 | `unification_skill.md` | Identity resolution, customer matching |
| 3 | `golden_skill.md` | Single customer view, aggregations |
| 4 | `segmentation_skill.md` | Audience segmentation, activation |

Optional:
- `idu_dashboard_skill.md` - Unification quality dashboard
- `analytics_skill.md` - Business intelligence dashboards

---

## Success Criteria

Pipeline is complete when:
- [✅] All databases created (stg, cdp_unif, gldn)
- [✅] All workflows run successfully
- [✅] Parent segment created and validated
- [✅] Test segments working
- [✅] All reports generated
- [✅] User confirmed and handed off

**Congratulations! You've built a complete CDP pipeline! 🚀**