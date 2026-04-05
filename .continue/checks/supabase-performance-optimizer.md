---
name: Supabase Performance Optimizer
---

Detect and fix performance issues in tables referenced by PR changes. Exit early if no relevant changes detected. Focus on measurable improvements with clear remediation paths.

## Early Exit Conditions

EXIT IMMEDIATELY if:

- No SQL files changed (*.sql, schema.sql, migrations)
- No database-related code changes (no .from(), .insert(), .update(), .delete() calls)
- Only documentation/README changes
- Only frontend/UI changes (CSS, HTML, React components without data fetching)
- Only test files changed (unless they reference new tables)

PROCEED ONLY if PR contains:

- New/modified migration files
- New/modified RLS policies
- Changes to files calling Supabase client methods
- Schema changes (CREATE TABLE, ALTER TABLE)

## Workflow

**CRITICAL: Push commits to the PR's existing branch, never create new branches.**

### 1. Pre-Flight Check (Cost: FREE)

Parse PR diff to identify table references:

- Scan *.sql files for CREATE/ALTER TABLE statements
- Parse migration files for table names
- Regex search code files for .from('table_name')
- Check type definitions for table references

**If table list is EMPTY → EXIT with comment:**

```markdown
<!-- perf-audit-bot -->
## ⚡ Performance Audit - No Action Needed

**Scope**: No database schema or table changes detected in this PR.

This PR doesn't modify database tables or RLS policies, so no performance audit is required.

---
*Automated performance audit • Skipped analysis*

```

**If table list has items → PROCEED to Step 2**

### 2. Filter for Performance-Relevant Changes (Cost: FREE)

Check if changes affect performance:

- Was RLS policy modified? → FLAG for auth initplan check
- Was table structure changed? → FLAG for index check
- Was it newly created? → FLAG for initial optimization

**If NO performance flags → EXIT with comment:**

```markdown
<!-- perf-audit-bot -->
## ⚡ Performance Audit - No Optimization Needed

**Scope**: {count} tables referenced, but no performance-impacting changes detected.

Changes to `{table_list}` don't affect RLS policies or indexes. No optimization needed.

---
*Automated performance audit • Skipped analysis*

```

### 3. Run Targeted Analysis (Cost: MCP CALLS)

**NOW and ONLY NOW, call Supabase MCP:**

For each flagged table:

- If has_rls_policy_changes → Check auth_rls_initplan lint results and retrieve policy definitions
- If has_structure_changes → Check for missing FK indexes and review query patterns

**Cost optimization:**

- Single MCP call per table (batched if possible)
- Only analyze tables with relevant changes
- Skip tables without performance flags

### 4. Classify Findings by Impact

**🔴 High Impact** - Auto-fix (clear performance degradation)

- Auth functions re-evaluated per row (proven fix: wrap in SELECT)
- Missing indexes on FK columns with JOIN evidence in codebase

**🟡 Medium Impact** - Recommend only (needs profiling)

- Potential composite indexes
- Policy consolidation opportunities

**Ignore everything else**

**If NO high-impact issues found → EXIT with minimal comment:**

```markdown
<!-- perf-audit-bot -->
## ⚡ Performance Audit - Looking Good

**Scope**: Analyzed {count} tables with performance-relevant changes.

No critical performance issues detected. Tables: `{table_list}`

---
*Automated performance audit • Last updated: {timestamp}*

```

### 5. Generate Migration (High Impact only)

**Only create migration if auto-fix criteria met:**

- Auth RLS initplan detected AND fix is mechanical
- FK index missing AND JOIN usage confirmed in codebase

File: `supabase/migrations/YYYYMMDDHHMMSS_performance_optimizations.sql`

```sql
-- Performance Optimizations for PR #{pr_number}
-- Auto-fix for confirmed performance issues
-- Tables: {list}

-- Fix: Auth RLS Initialization Plan
-- Impact: Prevents re-evaluation of auth.uid() for each row
-- Detection: Supabase linter flag 0003_auth_rls_initplan
-- Before: USING (auth.uid() = user_id)
-- After: USING ((select auth.uid()) = user_id)

{FOR EACH affected policy:}
DROP POLICY IF EXISTS "{policy_name}" ON {schema}.{table};

CREATE POLICY "{policy_name}" ON {schema}.{table}
FOR {operation}
USING ({optimized_condition})
{if insert/update: WITH CHECK ({optimized_condition})};
-- Optimization: Wrap auth.uid() in SELECT for single evaluation per query

-- Add missing indexes (only with JOIN evidence)
CREATE INDEX IF NOT EXISTS idx_{table}_{column}
ON {schema}.{table}({column});
-- Purpose: Found JOIN on this column in {file_reference}

-- Rollback instructions:
-- DROP POLICY "{policy_name}" ON {schema}.{table};
-- {original CREATE POLICY statement}
-- DROP INDEX IF EXISTS idx_{table}_{column};

```

### 6. Commit (High Impact only)

Message format:

```
perf: optimize {table_list} RLS policies and indexes

- Fix auth RLS initplan for {count} policies
- Add indexes for {column_list}
- Expected: 10-100x improvement on large result sets

Automated performance optimization.

```

### 7. Post or Update Comment

**BEFORE posting, check for existing comments:**

1. Search PR comments for marker: `<!-- perf-audit-bot -->`
2. If found → UPDATE that comment
3. If not found → CREATE new comment

**Comment template (only if changes made):**

```markdown
<!-- perf-audit-bot -->
## ⚡ Performance Audit Results

**Scope**: {count} tables with performance-relevant changes
**Issues Fixed**: {high_count}🔴

| Table | Issue | Expected Improvement | Status |
|-------|-------|---------------------|--------|
| `{name}` | {description} | {impact_description} | ✅ Fixed |

### Changes Applied
- **{table}**: Fixed {issue_count} RLS policies
  - Changed `auth.uid()` → `(select auth.uid())`
  - Impact: 10-100x faster on large result sets (proven optimization)
- Migration: `{filename}`

**Why this matters:**
Without this fix, `auth.uid()` is called for every row returned by the query. With the fix, it's called once per query. On a query returning 1,000 rows, this reduces auth function calls from 1,000 to 1.

{if medium priority issues exist:}
### Additional Recommendations (requires profiling)
- **{table}**: {suggestion} - Run `EXPLAIN ANALYZE` to verify impact

---
*Automated performance audit • Last updated: {timestamp} • [Performance docs](<https://supabase.com/docs/guides/database/postgres/row-level-security#call-functions-with-select>)*

```

**The HTML comment `<!-- perf-audit-bot -->` MUST be the first line for detection to work.**

## Cost Optimization Strategy

**Checkpoint 1: Parse Diff (FREE)**

- PR changes → Extract table names
- Found tables? → PROCEED
- No tables? → EXIT (no comment spam)

**Checkpoint 2: Flag Relevance (FREE)**

- Tables found → Check for performance-relevant changes
- RLS/index changes? → PROCEED
- Only data changes? → EXIT (acknowledge + skip)

**Checkpoint 3: MCP Analysis (MINIMIZE CALLS)**

- Relevant changes → Call Supabase MCP
- ONLY for flagged tables
- ONLY for specific lint checks (auth_rls_initplan)
- Batch requests where possible

**Checkpoint 4: Auto-Fix Gate (FREE)**

- Lint results → Filter to proven optimizations
- High impact found? → Create migration + commit
- Nothing actionable? → EXIT (positive comment, no spam)

## Automated Fix Criteria

**Auto-fix (proven ROI):**

- Auth RLS initplan (0003_auth_rls_initplan lint flag)
    - Mechanical transformation: `auth.X()` → `(select auth.X())`
    - Proven 10-100x improvement
    - Zero risk (functionally equivalent)

**Recommend only:**

- Indexes without clear JOIN evidence
- Schema changes requiring business context

**Never auto-fix:**

- Speculative optimizations
- Changes requiring query profiling
- Anything without proven impact

## Common Optimizations

### Auth RLS Initplan Fix

**Problem**: `auth.uid()` evaluated for every row

**Fix**: `(select auth.uid())` evaluated once per query

**Impact**: 10-100x faster on large result sets

Before:

```sql
USING (auth.uid() = user_id)

```

After:

```sql
USING ((select auth.uid()) = user_id)

```

### Foreign Key Indexes

**Problem**: Sequential scans on JOINs

**Fix**: Index FK columns

**Impact**: O(n) → O(log n) lookups

```sql
CREATE INDEX idx_{table}_{fk_column}
ON {schema}.{table}({fk_column});

```

## Rules

- Exit early and often - Don't waste compute on irrelevant PRs
- Minimize MCP calls - Only query what you need to fix
- No comment spam - If nothing to fix, post minimal/no comment
- Proven fixes only - Auth initplan is the gold standard
- ALWAYS check for existing comment before posting
- Batch operations where possible to reduce API calls

## Edge Cases

- No tables detected → EXIT immediately (no comment)
- Tables found but no perf changes → EXIT with skip comment
- Only data migrations (INSERT/UPDATE) → EXIT (no comment)
- Auth initplan already optimized → Acknowledge in comment
- MCP unavailable → Post manual audit instructions
- Existing bot comment → UPDATE it, never duplicate

## Success Metrics

**Cost efficiency:**

- Less than 5 MCP calls per PR on average
- Zero MCP calls on non-database PRs
- No unnecessary migrations created

**Impact:**

- Only auto-fix issues with 10x+ proven improvement
- Zero false positives
- Clear before/after in every change

## Example Flows

**Example 1: New RLS policy (FIX)**

```
PR opened with new RLS policy
→ Step 1: Parse diff → Found "users" table
→ Step 2: Check flags → RLS policy modified ✓
→ Step 3: MCP call → auth_rls_initplan warning found
→ Step 4: Generate fix → Wrap auth.uid() in SELECT
→ Step 5: Commit → Push migration
→ Step 6: Comment → Report fix with expected impact

```

**Example 2: README changes (SKIP)**

```
PR opened with README changes
→ Step 1: Parse diff → No tables found
→ EXIT (no comment, no cost)

```

**Example 3: Data seed (SKIP)**

```
PR opened with data seed
→ Step 1: Parse diff → Found "products" table
→ Step 2: Check flags → Only INSERT statements (no schema/RLS changes)
→ EXIT with skip comment (low cost)

```