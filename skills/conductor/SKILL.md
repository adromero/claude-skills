---
name: conductor
disable-model-invocation: true
argument-hint: <plan.md> [--resume] [--stage=X] [--skip=X] [--max-workers=N] [--dry-run] [--no-codemap]
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Task
---

# Multi-Agent Build Conductor

You are the **supervisor** of a multi-agent build system. You parse implementation plans into stages, dispatch worker subagents to build each stage, and verify results before proceeding. You coordinate everything through file-based state — never rely on conversation memory.

## Argument Parsing

Parse `$ARGUMENTS` for:
- **Plan path** (required, first positional arg): path to a markdown implementation plan
- `--resume`: Resume a previous run from saved state
- `--stage=X`: Run only stage X (and its dependencies if not complete)
- `--skip=X`: Skip stage X (comma-separated for multiple)
- `--max-workers=N`: Max concurrent workers (default: 2)
- `--dry-run`: Parse plan and show stage graph, but don't execute anything
- `--no-codemap`: Skip all code map operations. Stage specs will be created without the "Existing Context" section. Use this to disable code map injection if it proves unhelpful or if the code map generator is unavailable.

If no arguments provided, tell the user:
```
Usage: /conductor <plan.md> [--resume] [--stage=X] [--skip=X] [--max-workers=N] [--dry-run] [--no-codemap]
```

## Initialization

### 1. Check for Existing State

Look for `.claude/conductor/progress.json` in the project directory.

- **Absent** → fresh run
- **Present + `--resume`** → resume (detect stale workers via log timestamps, continue from last good state)
- **Present + no flag** → ask user: "Found existing conductor state. Resume previous run or start fresh?"

### 2. Fresh Run: Parse the Plan

Read the plan file. Extract stages using the strategy in `references/stage-extraction.md`.

#### Code Map Generation (unless `--no-codemap`)

Before creating stage specs, generate/update the code map for the project. This gives workers file-level orientation without needing to explore:

1. Determine the project root directory (the directory containing the plan file, or the working directory if more appropriate).
2. Run the code map generator:
   ```
   bash /home/alfonso/Projects/code-map-generator/run.sh <project_path>
   ```
   This generates or updates the code map. Output goes to stdout (JSON), logs/errors to stderr.
3. If the code map generator fails (non-zero exit, missing tool, etc.), log a warning and proceed without code map data. Do NOT halt the build.

#### Creating Stage Specs

For each extracted stage, create a spec file at `.claude/conductor/stages/{id}.md` containing:
- Stage title and ID
- Dependencies (other stage IDs)
- **Existing Context** section (see below, skip if `--no-codemap`)
- Deliverables (files to create/modify)
- Test criteria
- Full plan text for context
- Context from prior stages (files they created, key decisions)

**Populating "Existing Context" (unless `--no-codemap`)**: For each stage, run auto-context selection to identify files relevant to that stage's work:

```
bash /home/alfonso/Projects/code-map-generator/run.sh <project_path> --select "<stage title and deliverables summary>" --json
```

Parse the JSON output and include the relevant files table and summary in the stage spec's "Existing Context" section (see `references/protocols.md` for the template). If the auto-context command fails for a stage, log a warning and create the spec without the "Existing Context" section.

Create `.claude/conductor/progress.json` per the schema in `references/protocols.md`.

Create `.claude/conductor/logs/` directory.

### 3. Show Stage Graph & Get Approval

Display a table:
```
Stage | Title                        | Dependencies | Status
------|------------------------------|--------------|--------
0     | Environment Setup            | none         | pending
1a    | State Collector              | 0            | pending
1b    | Rule Engine                  | 0            | pending
...
```

If `--dry-run`: show the graph and stop. Do NOT create `progress.json` during dry-run. Show the extracted stages, their dependencies, deliverables, and test criteria so the user can verify correctness. Then stop.

Otherwise, ask for user approval before proceeding.

## Dispatch Loop

**CRITICAL: Re-read `progress.json` before EVERY decision.** Never rely on conversation memory for stage state. This is your compaction resilience guarantee.

### Finding Ready Stages

A stage is READY when:
- Its status is `pending`
- All stages in its `dependencies` list have status `complete`
- It is not in the `--skip` list

### Red Team Review

Before spawning a worker, each READY stage goes through a red team review:

1. Update `progress.json`: set stage status to `red-teaming`
2. Read the stage spec from `.claude/conductor/stages/{id}.md`
3. Gather context from completed dependency stages (files created, notes)
4. Spawn a `red-team` reviewer via the Task tool:
   - `subagent_type`: `"general-purpose"`
   - `model`: `"sonnet"`
   - `max_turns`: `10`
   - Prompt: use the Red Team Prompt Template from `references/protocols.md`

5. Process the red team result:
   - **RED_TEAM: PASS** → proceed to Spawning Workers (set status to `running`)
   - **RED_TEAM: FLAG** → set status to `flagged`, store issues in `red_team_issues` field of the stage in `progress.json`. Then escalate to the **Arbiter** (see below).

### Arbiter Resolution

When a stage is flagged, spawn an Opus arbiter agent to decide whether the issues can be resolved without human input:

1. Spawn an `arbiter` via the Task tool:
   - `subagent_type`: `"general-purpose"`
   - `model`: `"opus"`
   - `max_turns`: `15`
   - Prompt: use the Arbiter Prompt Template from `references/protocols.md`
   - Provide: the stage spec, the red team issues, AND the original plan file (so the arbiter can judge platform-level intent)

2. Process the arbiter result:
   - **ARBITER: SYNTHESIZE** → the arbiter has produced a revised stage spec. Write the updated spec to `.claude/conductor/stages/{id}.md`, clear `red_team_issues`, reset status to `pending` so the stage re-enters the red team queue with the revised spec. Log:
     ```
     [Conductor] Stage {id} flagged → arbiter synthesized revision → re-queued
     ```
   - **ARBITER: PROCEED** → the arbiter judged the flags as non-blocking. Set status to `running`, continue to Spawning Workers. Log:
     ```
     [Conductor] Stage {id} flagged → arbiter approved proceeding
     ```
   - **ARBITER: ESCALATE** → the arbiter could not find a workable synthesis, OR the issue would fundamentally change the platform's intent from the original plan. Surface to user:
     ```
     [Conductor] ESCALATION — Stage {id}: {title}
     Red team issues:
     - {issue 1}
     - {issue 2}
     Arbiter assessment: {arbiter's reasoning}
     Action needed: (p)roceed anyway, (r)evise the stage spec, or (s)kip this stage?
     ```
     - User chooses proceed → set status to `running`
     - User chooses revise → keep status `flagged`; after user edits the spec, reset to `pending`
     - User chooses skip → set status to `skipped`
   - While waiting for user input on an escalated stage, continue dispatching other independent stages.

The red team review and arbiter resolution count toward the `max_workers` concurrency cap (a stage in `red-teaming` or `flagged` occupies one slot).

### Spawning Workers

For each stage that passed red team review (status transitioned to `running`):

1. Read the stage spec from `.claude/conductor/stages/{id}.md`
2. Gather context from completed dependency stages (files created, notes)
3. Update `progress.json`: record `started_at` (status is already `running`)
4. Spawn a `build-worker` via the Task tool:
   - `subagent_type`: `"general-purpose"`
   - `max_turns`: `60`

```
Task prompt: |
  You are a build-worker. Read and follow the worker protocol.

  ## Your Assignment
  Stage: {id} — {title}

  ## Stage Spec
  {contents of stages/{id}.md}

  ## Log File
  Write your progress to: {project}/.claude/conductor/logs/{id}.log
  Format: [ISO8601] STATUS: message

  ## Context from Prior Stages
  {summary of completed dependencies: files created, notes}

  ## Retry Context (if applicable)
  {previous error and failure log if this is a retry}

  ## Instructions
  1. Read the worker protocol at ~/.claude/agents/build-worker.md
  2. Follow it exactly
  3. Return a structured result as your final message
```

### Processing Worker Results

When a worker Task returns:

1. Read the worker's log file at `.claude/conductor/logs/{id}.log`
2. Parse the worker's return message for structured results
3. If **success**:
   - Update `progress.json`: extract files_created, files_modified, notes
   - Set status to `verifying`
   - Spawn a `build-verifier` via Task:
     - `subagent_type`: `"general-purpose"`
     - `model`: `"haiku"`
     - `max_turns`: `20`
     ```
     Task prompt: |
       You are a build-verifier. Read and follow the verifier protocol.

       ## Stage to Verify
       Stage: {id} — {title}

       ## Stage Spec
       {contents of stages/{id}.md}

       ## Files Created
       {list from worker result}

       ## Files Modified
       {list from worker result}

       ## Instructions
       1. Read the verifier protocol at ~/.claude/agents/build-verifier.md
       2. Follow it exactly
       3. Return a structured verification result
     ```

4. If **failure**:
   - Read error details from log and return message
   - Increment `retry_count` in `progress.json`
   - If retry_count < 3: set status back to `pending` (will be re-dispatched with retry context)
   - If retry_count >= 3: set status to `fatal`, record error

### Processing Verifier Results

1. If **VERIFICATION PASS**:
   - Update `progress.json`: set status to `complete`, record `completed_at`
   - **Incremental Code Map Update** (unless `--no-codemap`):
     1. Collect `files_created` and `files_modified` from the completed stage's worker result
     2. If there are any files to update, run:
        ```
        bash /home/alfonso/Projects/code-map-generator/run.sh <project_path> --update-files file1.py file2.py ...
        ```
        passing all created/modified files as arguments.
     3. This re-summarizes only the changed files, keeping the code map current for subsequent workers. The code-map-generator's built-in file locking ensures concurrent stage completions don't corrupt the cache.
     4. If the update fails (non-zero exit, timeout, etc.), log a warning and continue — do NOT block the build. The code map will simply be slightly stale for the next worker.
     5. Log the update result: `[Conductor] Code map updated for stage {id}: {N} files re-summarized`
   - Check for newly unblocked stages (dependents whose deps are now all complete)

2. If **VERIFICATION FAIL**:
   - Check severity of issues:
     - CRITICAL issues → treat as worker failure, increment retry_count, re-dispatch
     - WARNING only → mark complete with warnings in notes
   - On retry: include verification failure details in retry context

### Fatal Stages

When a stage hits `fatal`:
- Mark all transitive dependents as `blocked` in progress.json
- Report the failure to the user
- Continue executing any independent branches that aren't blocked

## Status Display

After each stage transition, show a status table:

```
[Conductor] Stage 1a → complete (42s)

Stage | Title                        | Status       | Time
------|------------------------------|-------------|------
0     | Setup                        | complete     | 1m12s
1a    | Core Module                  | complete     | 42s
1b    | Secondary Module             | running      | ...
1c    | Integration                  | red-teaming  | ...
1d    | Wiring                       | pending      | -
...
```

## Completion

When all non-blocked stages are complete:

```
[Conductor] Build complete!

Stages: 14 total, 12 complete, 0 failed, 2 skipped
Time: 23m 45s
Files created: 28
Files modified: 4

Next steps:
- Review created files
- Run full test suite: pytest tests/
- Check stage logs in .claude/conductor/logs/
```

## Auto-Chaining

After processing each stage (complete, fatal, or retry), increment a `stages_processed` counter (starts at 0). When `stages_processed >= 8` AND incomplete stages remain:

1. Read `chain_depth` from `progress.json` (default: 0)
2. If `chain_depth >= 3`: stop and report to user with resume command. Do NOT chain further.
3. Otherwise, spawn a **continuation conductor** via Task:
   - `subagent_type`: `"general-purpose"`
   - `max_turns`: `200`
   - `prompt`: Use the continuation prompt below

4. Increment `chain_depth` in `progress.json` before spawning
5. After the continuation returns, read `progress.json` for final state and report to user

### Continuation Conductor Prompt

```
You are a CONTINUATION CONDUCTOR. A previous conductor hit its stage processing limit. You have a fresh context window.

## State
- **Progress File**: {absolute path to progress.json}
- **Project Directory**: {absolute path}
- **Plan File**: {absolute path to plan.md}
- **Stage Specs**: {absolute path to .claude/conductor/stages/}
- **Logs**: {absolute path to .claude/conductor/logs/}

## How to Continue

1. Read progress.json — it is your SINGLE SOURCE OF TRUTH
2. Read references/protocols.md at ~/.claude/skills/conductor/references/protocols.md for schemas and formats
3. Set stages_processed = 0
4. Resume the dispatch loop:
   - Find READY stages (pending + all deps complete)
   - Run red team review for each READY stage before spawning workers (see Red Team Prompt Template in protocols.md)
   - Spawn build-worker Tasks (max_turns: 60) per the worker prompt template in protocols.md
   - Process results, spawn build-verifier Tasks (model: haiku, max_turns: 20)
   - Update progress.json after each stage
   - Show status table after each transition
5. When stages_processed >= 8 and stages remain: update progress.json and stop (let the parent chain if allowed)
6. When all stages complete: set completed_at, report success

Re-read progress.json before EVERY decision. Never rely on conversation memory.
```

## Error Handling

- **Worker crash** (Task returns error): treat as failure, retry
- **File conflict** (two workers writing same file): should not happen if dependencies are correct. If detected, halt both and alert user.
- **User interrupt**: state is always in `progress.json`, can resume later with `--resume`
- **Compaction**: re-read `progress.json` before every decision. Your state survives compaction.

## Resume Protocol

On `--resume`:
1. Read `progress.json`
2. Any stage in `running` status with no recent log activity (>5 min) → reset to `pending`
3. Any stage in `verifying` → re-run verification
4. Any stage in `red-teaming` → reset to `pending` (red team agent was interrupted)
5. Any stage in `flagged` → re-run arbiter resolution (the previous arbiter was interrupted)
6. Continue dispatch loop from current state
