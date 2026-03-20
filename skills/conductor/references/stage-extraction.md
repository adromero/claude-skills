# Stage Extraction Strategy

How to parse an arbitrary markdown implementation plan into structured stages.

## Extraction Patterns

Try patterns in order. Use the first one that produces results.

### Pattern 1: `### Stage X: Title` (preferred)

Regex: `^###\s+Stage\s+(\w+):\s+(.+)$`

Captures stage ID (e.g., `0`, `1a`, `2b`, `3d-3e`) and title. This is the most explicit format and should be used when available.

Example matches:
- `### Stage 0: Environment Setup` → id: `0`, title: `Environment Setup`
- `### Stage 1a: State Collector` → id: `1a`, title: `State Collector`
- `### Stages 3d-3e: Offline Degradation + Memory Pressure` → id: `3d-3e`, title: `Offline Degradation + Memory Pressure`

### Pattern 2: `### Step N:` or `### Phase N:`

Regex: `^###\s+(?:Step|Phase)\s+(\d+):\s+(.+)$`

Captures numeric ID and title. Less common but used in some plan formats.

### Pattern 3: H3s Under Build Section

If the plan has a section like `## Build Order`, `## Implementation`, `## Implementation Plan`, or `## Steps`, extract all H3 headers within that section as stages.

Regex for section: `^##\s+(?:Build Order|Implementation(?:\s+Plan)?|Steps)\s*$`
Then extract H3s within: `^###\s+(.+)$`

Assign sequential numeric IDs (0, 1, 2, ...) if no explicit IDs in headers.

### Pattern 4: Fallback — H2 Sections

If no H3 stages found, treat top-level H2 sections as stages (excluding obvious non-stage sections like "Context", "Overview", "Prerequisites", "Verification", "Key Design Decisions", "Reference Patterns").

## Dependency Extraction

### Explicit Dependencies

Scan stage text for:
- "depends on Stage X" / "depends on stages X, Y"
- "after Stage X" / "after stages X and Y"
- "requires Stage X" / "requires X to be complete"
- "blocked by Stage X"

Regex: `(?:depends?\s+on|after|requires|blocked\s+by)\s+[Ss]tages?\s+([\w,\s]+(?:and\s+\w+)?)`

### Hierarchical IDs

Stages with hierarchical IDs imply dependencies:
- `1a`, `1b`, `1c` are parallel (no deps on each other, only on prior group)
- `1d` depends on all of `1a`, `1b`, `1c` (the "d" suffix after a/b/c implies "wire together")
- `2a` depends on the completion of Stage group 1 (specifically `1d` if it exists, otherwise all `1x` stages)

Rules:
1. Same-level siblings (1a, 1b, 1c) depend on the prior group's terminal stage
2. A terminal stage (1d after 1a-1c) depends on all same-group siblings
3. Next group's first stages (2a) depend on the prior group's terminal stage
4. Combined stages (3d-3e) are treated as a single stage that depends on its group's prior stages

### File-Based Dependencies

If two stages reference the same file (one creates, another modifies), the modifier depends on the creator:
- Stage A: `CREATE: gateway/queue.py`
- Stage B: `MODIFY: gateway/queue.py` → B depends on A

Scan for:
- Create verbs: "create", "new file", "add file", "write"
- Modify verbs: "modify", "update", "extend", "add to", "wire", "integrate"

### Overlap Detection

If two stages in the same dependency level both CREATE files in the same directory, flag as potential conflict (warn user, don't auto-resolve).

## Test Criteria Extraction

Scan each stage's text for test criteria:

1. **Explicit test lines**: `**Test:**` or `**Test (...):**` — everything after this marker until the next stage header or blank line
2. **Verify/confirm language**: sentences containing "verify", "confirm", "check that", "should", "must"
3. **Command patterns**: backtick-enclosed commands that look like test commands (e.g., `python -c "..."`, `pytest`, `curl`, `systemctl status`)
4. **"Done When" markers**: `**Done When:**` or similar — captures acceptance criteria

## Deliverable Extraction

Scan each stage for files to create or modify:

1. **Backtick-quoted paths**: after create/modify verbs — e.g., `` `brainstem/collector.py` ``
2. **File descriptions**: "Create `X`", "`X`: description" patterns
3. **Directory structure blocks**: fenced code blocks showing file trees

Regex for file paths: `` `([a-zA-Z0-9_./\-]+\.\w+)` `` (backtick-quoted, has extension)

Classify as CREATE or MODIFY:
- CREATE: "create", "new", "add" verbs before the path, or path is in a "NEW" section
- MODIFY: "modify", "update", "extend", "add to", "wire" verbs, or marked with "MODIFY:" prefix

## Overlap Note for Parallel Stages

Specifically for the H1 plan, note these patterns:
- Stage `4 (partial)` explicitly says "can overlap 2b" — extract as having same deps as 2b (depends on Stage 0 + Stage 1d), not depending on 2b
- Combined stages like `3d-3e` get a single combined ID

## Ambiguity Handling

When extraction is ambiguous:

1. **Multiple possible dependency graphs**: show the user both interpretations, ask which is correct
2. **Stage boundaries unclear**: show extracted stages with their text ranges, ask user to confirm or adjust
3. **Missing test criteria**: flag stages without test criteria, suggest the user add `**Test:**` lines
4. **File ownership conflicts**: if two parallel stages touch the same file, ask user to confirm they're truly parallel or need sequencing

Always show the extracted result to the user for confirmation before proceeding, even in non-dry-run mode.

## Output Format

After extraction, produce a structured summary:

```
Extracted {N} stages from {plan_file}:

Stage | Title                              | Deps      | Deliverables | Tests
------|------------------------------------|-----------|--------------|------
0     | Environment Setup                  | none      | 8 files      | 2
1a    | State Collector                    | 0         | 3 files      | 1
1b    | Rule Engine                        | 0         | 2 files      | 1
1c    | Action Executor                    | 0         | 1 file       | 1
1d    | Complete Brainstem Loop            | 1a,1b,1c  | 1 file       | 4
...

Dependency graph:
  0 → 1a, 1b, 1c → 1d → 2a → 2b, 4 → 2c → 2d → 3a → 3b → 3c
                                                      → 3d-3e
```
