# APS Claude Tools vs TD Skills — Comparison & Gap Analysis

This document compares the **aps_claude_tools-main** reference agent code (7 production CDP plugins) with the **TD Skills** and **custom skills** used in this project, focusing on staging, unification, ingestion, and orchestration.

---

## 1. Architecture Overview

| Aspect | aps_claude_tools-main | TD Skills (td-skills-repo) | Custom Skills (td-poc, td-poc-staging, td-profiling) |
|--------|----------------------|---------------------------|------------------------------------------------------|
| **Format** | Plugin (`prompt.md` + `agents/` + `commands/`) | Skill (`SKILL.md` only) | Skill (orchestrator ~39KB + staging ~36KB + profiling) |
| **Execution model** | Sub-agents delegated via Task tool | Documentation generation for Confluence | Orchestrator delegates to specialist skills |
| **Installable** | Yes (`plugin.json`, independently installable) | Yes (symlinked from `td-skills-repo`) | Project-specific (not portable) |
| **SQL generation** | Agents generate `.sql` files directly | Documents existing SQL patterns | 17 inline SQL patterns Claude follows to generate |
| **Workflow automation** | Full deploy + execute + monitor + validate | Syntax reference only | Full deploy + execute + monitor + validate (td-poc-staging) |
| **Config management** | `src_params.yml` with dependency groups | N/A | Progressive hierarchy (`.env` -> `src_params.yml` with dependency groups) |
| **User interaction** | Minimal (config inputs upfront) | None (generates docs) | Interactive (`AskUserQuestion` checkboxes) |

---

## 2. Pipeline Coverage Matrix

| Pipeline Stage | aps_claude_tools Plugin | TD Skill | Custom Skill | Gap? |
|---------------|------------------------|----------|-------------|------|
| **Ingestion** | `cdp-ingestion` (6+ connectors: BigQuery, Klaviyo, Shopify, OneTrust, Pinterest, SFTP) | `td-aps-ingestion` (docs only) | Not covered | Yes — no ingestion automation |
| **Hist-Union** | `cdp-histunion` (watermark, `inc_log`, schema validation) | None | Not covered | Yes — no hist-union capability |
| **Profiling** | None | None | `td-profiling` (11 queries/table, parallel 3-at-a-time, 7 phases) | **Unique to this project** |
| **Staging** | `cdp-staging` (44KB agent, 9-step mandatory sequence) | `td-aps-staging` (docs only) | `td-poc-staging` (17 SQL patterns, 6 sub-steps, P1 incremental + DIG generation) | P0 gaps fixed; P1/P2 added |
| **Post-Staging** | None | None | `td-poc` Stage 4 (grain detection, hierarchy, unification readiness) | **Unique to this project** |
| **Unification** | `cdp-unification` (4 sub-agents, prep tables, `unify.yml`) | `td-aps-id-unification` (docs only) | `td-poc` Stage 5 (framework documented, sparse impl) | Yes — needs implementation |
| **IDU QA** | `cdp-idu-qa` (11-step overmerge analysis, HTML dashboard) | None | Not covered | Yes — no QA capability |
| **Hybrid IDU** | `cdp-hybrid-idu` (Snowflake + Databricks, convergence loops) | None | Not covered | N/A (POC scope is TD-only) |
| **Golden Layer** | None | `td-aps-golden` (docs only) | `td-poc` Stage 6 (briefly documented) | Yes — needs implementation |
| **Segments** | None | None | `td-poc` Stage 7 (briefly documented) | Yes — needs implementation |
| **Orchestration** | `cdp-orchestrator` (full automation: generate -> deploy -> execute -> monitor -> validate) | `td-wf-digdag`, `td-wf-workflow-management` (reference/ops) | `td-poc` Stage 3f (partial MCP-based) | Yes — execution loop gaps |

---

## 3. Staging Deep Comparison (Critical)

### 3.1 SQL Pattern Comparison

| Pattern | cdp-staging (aps_claude_tools) | td-poc Stage 3 (this project) | Verdict |
|---------|-------------------------------|-------------------------------|---------|
| **Null cleansing** | `NULLIF(NULLIF(TRIM(UPPER(col)),''),'NONE','NULL','N/A')` | `nullif(lower(ltrim(rtrim(col))),'null')` chain covering 8+ variants (`'n/a'`, `'na'`, `'none'`, `'unknown'`, `'-'`, `'.'`, empty) | **td-poc is richer** — more sentinel values covered |
| **Email** | 4 outputs: cleaned, `_std` (validated), `_hash` (SHA256), `_valid` flag | 3 outputs: `valid_email_flag`, `trfmd_email` (cleaned), invalid list exclusion via lookup JOIN | td-poc has richer invalid-list exclusion; aps has SHA256 hashing |
| **Phone** | 4 outputs: preclean, `_std` (10/11 digit logic), `_hash`, `_valid` | 1 output: `trfmd_phone` (digits-only via `REGEXP_EXTRACT_ALL`) | **GAP** — td-poc missing phone standardization (10/11 digit) |
| **Date/Timestamp** | **4 mandatory outputs**: original, `_std` (VARCHAR), `_unixtime` (BIGINT), `_date` (VARCHAR) with multi-format `COALESCE` chain | **4 mandatory outputs**: original, `_std`, `_unixtime`, `_date` with multi-format `COALESCE(TRY(DATE_PARSE(...)))` chain (Pattern 9) | **FIXED** — td-poc-staging now has all 4 outputs |
| **JSON extraction** | Mandatory auto-detection, 2-level key extraction, `NULLIF(UPPER(json_extract_scalar(...)))`, array handling via `TRY_CAST` | Pattern 16: auto-detection + scalar extraction (`json_extract_scalar`), nested 2-level support, array handling, special char key syntax | **FIXED** — Pattern 16 in td-poc-staging |
| **Deduplication** | CTE-based `ROW_NUMBER` with `partition_columns`, dependency groups, upsert (DELETE+INSERT) | Pattern 17: CTE `ROW_NUMBER() OVER(PARTITION BY ... ORDER BY time DESC)` + upsert SQL (DELETE+INSERT) | **FIXED** — Pattern 17 in td-poc-staging |
| **Boolean** | `VARCHAR` `'TRUE'`/`'FALSE'` | `VARCHAR` `'True'`/`'False'` | Equivalent (case style differs) |
| **Names** | In-place `UPPER` transform (keeps original column name) | Title case via `array_join(transform(split(...)))` with `trfmd_` prefix | **td-poc is richer** — proper title case |
| **Full name** | Not mentioned | NULL-safe derived from `trfmd_first_name` + `trfmd_last_name` using `filter(ARRAY[...], x -> x IS NOT NULL)` | **Unique to td-poc** |
| **Financial** | `ROUND(TRY_CAST(col AS DOUBLE), 2)` | Full chain: parenthetical negatives `(100)` -> `-100`, currency symbols, comma removal, `try(cast(... as double))` | **td-poc is richer** |
| **Gender** | Not specifically addressed | Full standardization (`'Female'`/`'Male'`/`'Other'`) | **Unique to td-poc** |
| **Age derived** | Not addressed | `date_diff('year', parse_chain, current_date)` from DOB | **Unique to td-poc** |
| **Season derived** | Not addressed | `CASE` on `month()` extraction | **Unique to td-poc** |
| **TD enrichment** | Not addressed | Full catalog: IP geo (9 functions), UA parsing (2 options), `TD_SESSIONIZE_WINDOW`, UTM extraction, currency conversion | **Unique to td-poc** (17 functions) |
| **Multi-space collapse** | Not addressed | `regexp_replace(col, '\\s+', ' ')` for categorical columns | **Unique to td-poc** |
| **Underscore-to-space** | Not addressed | Title case with `split(lower(trim(col)), '_')` variant | **Unique to td-poc** |

### 3.2 File Generation Comparison

| Artifact | cdp-staging (aps) | td-poc Stage 3 (this project) |
|----------|-------------------|-------------------------------|
| **Incremental SQL** | `staging/queries/{src_db}_{table}.sql` with `WHERE time > inc_log` watermark | `workflows/<project>/staging/queries/{db}_{table}.sql` with `inc_log` watermark pattern (P1) | **FIXED** — P1 in td-poc-staging |
| **Init SQL** | `staging/init_queries/{src_db}_{table}_init.sql` (full scan, first run) | Init SQL template in td-poc-staging P1 incremental section | **FIXED** — P1 in td-poc-staging |
| **Upsert SQL** | `staging/queries/{src_db}_{table}_upsert.sql` (DELETE+INSERT for dedup) | Upsert SQL template in td-poc-staging P1 incremental section | **FIXED** — P1 in td-poc-staging |
| **Metadata SQL** | `staging/queries/capture_staging_metadata.sql` (auto audit trail) | Metadata capture SQL template in td-poc-staging P2 section | **FIXED** — P2 in td-poc-staging |
| **Config YAML** | `staging/config/src_params.yml` with `dependency_groups`, per-table `has_dedup`, `partition_columns`, `mode` | `config/src_params.yml` with `dependency_groups`, per-table `has_dedup`, `partition_columns`, `mode` (P1) | **FIXED** — P1 in td-poc-staging |
| **DIG workflow** | `staging/staging_transformation.dig` — loop-based, wave execution, parallel, conditional init/incremental | `staging_transformation.dig` — loop-based `for_each>` wave execution, `_parallel`, conditional init/incremental (P1) | **FIXED** — P1 in td-poc-staging |
| **schema_map.yml** | Not used | Auto-generated from profiling, maps `src` -> `prp` columns | **Unique to td-poc** |

### 3.3 Staging Workflow Comparison

| Step | cdp-staging (aps) | td-poc Stage 3 (this project) |
|------|-------------------|-------------------------------|
| 1 | Table existence validation (`DESCRIBE`) | Profiling already validated (Phase 2) |
| 2 | Metadata collection (column count) | Schema from profiling profiles JSON |
| 3 | Deduplication logic determination | Not addressed |
| 4 | **JSON column detection (MANDATORY)** | Profiling detects; no staging pattern to consume |
| 5 | Dynamic JSON extraction | Not addressed in staging |
| 6 | Join processing (lookup tables) | Lookup JOINs from profiling choices |
| 7 | SQL generation (Clean -> Join -> Dedupe) | SQL generation (null cleanse -> trfmd_ -> derived -> enrichment) |
| 8 | Mandatory validation checks | Test via MCP with LIMIT 100 (iterative) |
| 9 | File creation + config update + git | Save SQL + update configs + git checkpoint |

---

## 4. Orchestration / Execution Comparison

| Capability | cdp-orchestrator (aps) | td-poc-staging Stage 3f (this project) |
|-----------|------------------------|---------------------------------------|
| **Deployment** | `td wf push` via Bash with 3-retry auto-fix (syntax errors, missing DBs, auth failures) | MCP-based deploy with 3-retry protocol (syntax errors, missing DBs, auth) |
| **Execution** | `td wf start` with session ID capture via regex parsing | MCP-based execution with session ID capture |
| **Monitoring** | 30s polling loop, 2-hour max wait, progress display with elapsed time | 30s polling loop, 2-hour max wait, status checking via `list_sessions` |
| **Post-execution validation** | SQL queries: table existence, row counts > 0, column verification per expected table | Row count validation (table existence + rows > 0) |
| **Error handling** | Structured: auto-fix (syntax) -> ask-user (DB missing, auth) -> retry up to 3x per deploy | Structured: auto-fix (syntax) -> ask-user -> retry up to 3x |
| **State tracking** | `pipeline_state.json` with per-phase status, session IDs, duration, timestamps | `.poc-state/current-poc.json` via Python `state_manager.py` |
| **TD Toolbelt** | Direct `td -k $API_KEY -e $ENDPOINT wf push/start/session` commands | MCP-only approach (no CLI fallback) |
| **Phase dependencies** | Enforced: validation between phases prevents proceeding on failure | Implicit: fix-and-retry but no validation gate |
| **Progress display** | TodoWrite-based real-time status updates in CLI | State manager updates (less visual) |

---

## 5. Features Unique to This Project (Not in aps_claude_tools)

| Feature | Skill | Why It Matters |
|---------|-------|----------------|
| **Data Profiling** (7-phase, 11 queries/table, parallel 3-at-a-time) | `td-profiling` | No equivalent in aps_claude_tools — discovers what transformations are needed before staging |
| **Post-Staging Analysis** (grain, hierarchy, identity coverage, unification readiness) | `td-poc` Stage 4 | Bridges staging to unification with data-driven recommendations |
| **TD Enrichment Catalog** (17 functions: IP geo, UA parsing, sessionization, currency) | `td-poc` (shared reference), `td-poc-staging` (Pattern 15) | cdp-staging has zero enrichment detection or application |
| **Interactive User Approval** (checkbox-driven per-table transformation choices) | `td-profiling` | cdp-staging generates SQL without user input on what to transform |
| **Lookup Table Detection** with role classification (exclusion, decoder, enrichment, threshold) | `td-profiling` | Automated discovery of small reference tables for JOIN enrichment |
| **Multi-PII Table Split Detection** (2+ PII categories sharing same ID) | `td-profiling` | Cleaner identity graph edges for unification |
| **Git Checkpoint Strategy** (per-stage, per-decision commits with co-author trailer) | `td-poc` | More granular audit trail than aps single-commit |
| **Configuration Hierarchy** (`.env` bootstrap -> `src_params.yml` runtime -> progressive population) | `td-poc` | Clear separation of secrets vs runtime config |
| **Lossless Transformation Guarantees** (6 explicit rules: TRY over CAST, preserve originals, key safety) | `td-poc-staging` | aps_claude_tools doesn't document these guarantees |
| **TD `time` Column Classification** (meaningful event time vs import timestamp vs garbage) | `td-profiling` | Critical for deciding incremental load strategy |
| **Bernoulli Sampling Strategy** (size-adaptive: full/<100K, 10%/<10M, 1%/>10M) | `td-profiling` | Avoids biased time-column filtering |

---

## 6. Recommended Additions (Prioritized) — Status Tracker

### P0 — Must Have (blocks staging quality) — ALL DONE

| Gap | Status | Implemented In | Details |
|-----|--------|---------------|---------|
| **Date 4-output** | **DONE** | `td-poc-staging` Pattern 9 | 4 mandatory outputs: original, `_std`, `_unixtime`, `_date` with multi-format `COALESCE(TRY(DATE_PARSE(...)))` chain |
| **JSON staging pattern** | **DONE** | `td-poc-staging` Pattern 16 | Auto-detection + scalar extraction, 2-level nested, array handling, special char key syntax |
| **Dedup CTE pattern** | **DONE** | `td-poc-staging` Pattern 17 | `ROW_NUMBER() OVER(PARTITION BY ... ORDER BY time DESC)` CTE + upsert SQL (DELETE+INSERT). Promoted from P2 |
| **Execution loop** | **DONE** | `td-poc-staging` Stage 3f | 4-step: Deploy (3-retry) -> Execute (session ID capture) -> Monitor (30s polling) -> Validate (row counts) |

### P1 — Should Have (production readiness) — ALL DONE

| Gap | Status | Implemented In | Details |
|-----|--------|---------------|---------|
| **Incremental processing** | **DONE** | `td-poc-staging` P1 section | `inc_log` watermark: init SQL (full scan) + incremental SQL (`WHERE time > inc_log`) + upsert SQL |
| **Loop-based DIG generation** | **DONE** | `td-poc-staging` P1 section | Dynamic `staging_transformation.dig` with `for_each>: wave`, `_parallel`, conditional init/incremental |
| **src_params.yml dependency groups** | **DONE** | `td-poc-staging` P1 section | `dependency_groups:` with per-table `has_dedup`, `partition_columns`, `mode` (inc/full) |

### P2 — Nice to Have (quality improvements) — ALL DONE

| Gap | Status | Implemented In | Details |
|-----|--------|---------------|---------|
| **Metadata capture SQL** | **DONE** | `td-poc-staging` P2 section | Per-table audit SQL: source DB, target table, transforms, row counts, timestamp |
| **Hash documentation** | **DONE** | `td-poc-staging` P2 section | SHA256 production upgrade path: `LOWER(TO_HEX(SHA256(CAST(UPPER(col) AS VARBINARY))))` |

### P3 — Future Enhancements

| Gap | What to Add | Source Reference | Impact |
|-----|-------------|-----------------|--------|
| **Hist-Union stage** | New Stage 2b: schema comparison between `_hist` and incremental tables, `UNION ALL` with column alignment, watermark tracking | `cdp-histunion/prompt.md` | Handles backfill scenarios with historical data |
| **IDU QA stage** | New Stage 5b: query `idu_qa_*` tables for overmerge analysis, bridging key detection, toxic value identification, generate QA report | `cdp-idu-qa/README.md` | Post-unification quality validation |

---

## 7. Summary Verdict

### aps_claude_tools Strengths
- Production-grade execution automation (deploy / monitor / retry / validate)
- Incremental processing with `inc_log` watermark pattern
- JSON auto-detection and 2-level extraction
- Deduplication with dependency wave execution
- Metadata capture for audit trails
- Cross-platform IDU (Snowflake, Databricks)
- Overmerge QA analysis with interactive HTML dashboards

### This Project's Strengths
- Data profiling (7-phase, parallel, 11 queries/table) — **no equivalent in aps**
- Post-staging analysis (grain, hierarchy, unification readiness) — **no equivalent in aps**
- TD enrichment detection and catalog (17 functions) — **no equivalent in aps**
- Interactive user approval (checkbox-driven per-table choices)
- Lookup table detection with role classification
- Multi-PII table split detection
- Lossless transformation guarantees (6 explicit rules)
- Configuration hierarchy with progressive population
- Git checkpoint strategy per stage

### Bottom Line

The two systems are **complementary, not competing**:

- **aps_claude_tools** excels at **execution mechanics** — how to deploy, run, monitor, and validate workflows
- **This project** excels at **data intelligence** — what transformations to apply, which tables to join, how to prepare for unification

Adopting the **P0 gaps** (date 4-output, JSON pattern, execution loop) would make `td-poc` a complete staging solution that combines the best of both worlds: intelligent data-driven transformation decisions with production-grade execution automation.

---

*Generated from analysis of `aps_claude_tools-main/` (7 plugins) vs `td-poc`/`td-profiling` custom skills + 6 TD reference skills*
