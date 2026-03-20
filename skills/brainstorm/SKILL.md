---
name: brainstorm
description: Multi-agent planning skill that creates rigorous plan documents through specialized synthesis and adversarial review. Handles bug fixes to full platforms with iterative user collaboration. Invoke with an idea description or --resume to continue a previous session.
argument-hint: <idea description> | <path/to/existing-doc.md> [idea description] | --resume <path/to/plans/name/status.md>
disable-model-invocation: true
allowed-tools: Agent, Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion
---

# Brainstorm: Multi-Agent Plan Synthesis

You are the **orchestrator** of a multi-agent brainstorming and planning system. You stay lightweight — dispatch agents, manage files, interact with the user. Heavy thinking is delegated to specialist agents.

All agent prompts live in `~/.claude/skills/brainstorm/prompts/`. Read the relevant prompt file, fill in template variables (marked with `{curly_braces}`), and pass the filled-in result as the prompt to the Agent tool.

## Handoff Protocol (Appended to All Agent Prompts)

Append this block to EVERY agent prompt before dispatching:

```
## Context Management

You are operating in a multi-agent system. Keep your context lean:

1. Write findings to your output file INCREMENTALLY as you work — do not accumulate everything in memory before writing.
2. If you've read more than 5 large files or made more than 20 tool calls, write a partial result to your output file immediately.
3. If you cannot complete your analysis, write what you have to your output file and create a handoff file at:
   {plan_directory}/artifacts/handoff-{your-role}.md
   The handoff file MUST contain:
   - What you completed
   - What remains
   - Key findings so far
   - File paths the continuation agent needs to read
4. Your return message should be a concise summary (under 500 words). Detailed findings belong in your output file, not your return message.
5. Always indicate in your return message whether you COMPLETED or need CONTINUATION.
```

---

## Argument Parsing

Parse `$ARGUMENTS`:

- **`--resume <path>`**: Resume from a saved status file. Read it and jump to the current phase.
- **File path detected** (argument contains a path to an existing `.md`, `.txt`, or similar file): This is a **seed document** — an existing architecture doc, PRD, design doc, RFC, or prior plan the user wants to build from. Read the file. If additional text follows the path, treat it as supplementary idea context. Proceed to Phase 0 with seed document mode.
- **Any other text**: Treat as a new idea description. Proceed to Phase 0 without a seed document.
- **Empty**: Use AskUserQuestion to ask the user to describe their idea.

**Detecting file paths**: If the first token of `$ARGUMENTS` looks like a file path (contains `/` or `.` with a file extension), attempt to read it. If the read succeeds, it's a seed document. If it fails, treat the entire argument as idea text.

---

## Phase 0: Setup & Triage

### 1. Capture the Idea

Store the raw idea text verbatim. This is injected into agent prompts as `{idea_text}`.

**If a seed document was detected**: Read the file and store its contents as `{seed_document}`. Copy the file into `artifacts/00-seed-document.md` for the record. If the user also provided idea text alongside the path, use that as `{idea_text}`. If only the file was provided, use AskUserQuestion to ask the user for a brief description of what they want to do with/build from this document — that becomes `{idea_text}`.

### 2. Name the Plan

Generate 3 kebab-case slug options based on the idea (e.g., `auth-token-refresh`, `dashboard-redesign`, `event-driven-platform`). Present them to the user via AskUserQuestion and let them pick or provide their own.

### 3. Create Directory Structure

```bash
mkdir -p <cwd>/plans/{plan-name}/artifacts
```

### 4. Classify Tier

Assess the idea's scope and assign a tier:

| Tier | Scope | Synthesis Agents | Red-Team Agents |
|------|-------|-----------------|-----------------|
| **patch** | Bug fix, small change, config tweak | Implementer, Risk Analyst | Devil's Advocate, Scope Auditor |
| **feature** | New feature, UI improvement, module addition | Architect, Implementer, Domain Expert, Risk Analyst | Devil's Advocate, Scope Auditor, Feasibility Checker |
| **system** | Platform, fork, major architecture, multi-service | Architect, Implementer, Domain Expert, Risk Analyst | Devil's Advocate, Scope Auditor, Feasibility Checker |

Present the tier to the user with a one-line justification. User confirms or overrides via AskUserQuestion.

### 5. Explore Project Context

If inside a project directory (has package.json, Cargo.toml, pyproject.toml, CLAUDE.md, go.mod, etc.):
- Scan project structure using Glob and Read
- Identify language, framework, conventions
- Write a concise project summary (max 300 words) as `{project_context}`

If not in a project: set `{project_context}` to "No project context available."

### 6. Write Initial State Files

Write `status.md` to the plan directory:

```markdown
# Brainstorm: {plan-name}

## Status
- **Phase**: 1
- **Tier**: {tier}
- **Seed Document**: {path to original file, or "None"}
- **Created**: {YYYY-MM-DD}
- **Last Updated**: {YYYY-MM-DD HH:MM}
- **Plan Directory**: {absolute path}
- **Resume Command**: `/brainstorm --resume {absolute path}/status.md`

## Original Idea
{idea text}

## Seed Document
{If a seed document was provided, note: "See artifacts/00-seed-document.md" and include a 2-3 sentence summary of what it contains. Otherwise: "None."}

## Project Context
{project summary or "No project context available."}

## Phase Progress
| Phase | Name | Status |
|-------|------|--------|
| 0 | Setup & Triage | completed |
| 0.5 | Auto-Context Selection | {pending or skipped} |
| 1 | Idea Challenge | pending |
| 2 | Synthesis | pending |
| 3 | User Checkpoint | pending |
| 4 | Red-Team | pending |
| 5 | Reconciliation | pending |
| 6 | Final Output | pending |
```

Write the original idea to `artifacts/00-original-idea.md`.

Initialize `decision-log.md`:

```markdown
# Decision Log: {plan-name}

| # | Phase | Decision | Rationale |
|---|-------|----------|-----------|
```

Update `status.md`: Phase 0 → completed, Phase 0.5 → in_progress (if code project), or Phase 1 → in_progress (if non-code).

---

## Phase 0.5: Auto-Context Selection

**Goal**: Pre-select relevant code context for each specialist so they receive targeted file content instead of exploring the codebase from scratch.

### Skip Conditions

Skip Phase 0.5 entirely and proceed to Phase 1 if ANY of the following are true:
- Not a code project (no `package.json`, `Cargo.toml`, `pyproject.toml`, `go.mod`, `CLAUDE.md`, etc. detected in Phase 0)
- No project directory detected
- No code map cache exists AND the project has 100+ files (generating a fresh map would be too slow)

If skipped, set `{relevant_files}` to empty string for all specialist prompts and set `{code_map_summary}` to empty string for Devil's Advocate. Proceed to Phase 1.

### 1. Generate/Update Code Map

Run the code map generator against the project:

```bash
$CODEMAP_CMD {project_path}
```

If `CODEMAP_CMD` is not set or the command fails (non-zero exit), log the error and skip the rest of Phase 0.5. Set all context variables to empty strings and proceed to Phase 1. **Phase 0.5 failure must never block brainstorm execution.**

### 2. Generate Code Map Summary for Devil's Advocate

Run:

```bash
$CODEMAP_CMD {project_path} --summary
```

Capture the output and store it as `{code_map_summary}`.

### 3. Run Multi-Role Context Selection

Run the context selector for all four specialist roles:

```bash
$CODEMAP_CMD {project_path} --select-for-roles '{"idea": "{idea_text_escaped}", "roles": ["architect", "implementer", "risk-analyst", "domain-expert"]}' --json
```

Where `{idea_text_escaped}` is the idea text with JSON-unsafe characters escaped.

Parse the JSON output. It returns per-role file lists:

```json
{
  "architect": ["path/to/file1.py", "path/to/file2.py"],
  "implementer": ["path/to/file3.py", "path/to/file4.py"],
  "risk-analyst": ["path/to/file5.py"],
  "domain-expert": ["path/to/file6.py", "path/to/file7.py"]
}
```

If the command fails, log the error, set all `{relevant_files}` to empty strings, and proceed.

### 4. Read Selected Files and Format Context

For each role, read the selected files and format them as markdown:

```markdown
### Pre-Selected Code Context

The following files have been identified as relevant to your analysis. You do NOT
need to explore the codebase — this context has been pre-selected for your role.

#### `path/to/file1.py`
\```python
{file contents}
\```

#### `path/to/file2.py`
\```python
{file contents}
\```
```

Store the formatted content for each role as `{relevant_files_architect}`, `{relevant_files_implementer}`, `{relevant_files_risk_analyst}`, `{relevant_files_domain_expert}`.

When filling specialist prompts later, use the role-specific variable as `{relevant_files}`.

### 5. Save Context Selection Artifact

Save the raw JSON output and metadata to `{plan_directory}/artifacts/00-context-selection.json` for debugging and review:

```json
{
  "timestamp": "{ISO8601}",
  "project_path": "{project_path}",
  "idea_text": "{idea_text}",
  "selection": { ...per-role file lists... },
  "code_map_summary_length": {char_count}
}
```

### 6. Update State

Update `status.md`: Phase 0.5 → completed, Phase 1 → in_progress.

---

## Phase 1: Idea Challenge (Interactive)

**Goal**: Stress-test the idea (and seed document, if provided) before investing in detailed planning.

### 1. Spawn Devil's Advocate

Read the prompt template from `~/.claude/skills/brainstorm/prompts/devils-advocate.md`.

Fill in template variables:
- `{plan_directory}`: absolute path to the plan directory
- `{idea_text}`: original idea
- `{mode}`: `idea`
- `{mode_target}`: `Idea`
- `{mode_description}`: `a raw idea before any planning has occurred`
- `{content}`: the idea text. **If a seed document exists**, append it after the idea text with a clear separator: `\n\n---\n\n## Existing Document (provided by user)\n\n{seed_document_contents}`. This gives the Devil's Advocate the full picture to challenge.
- `{prior_critique}`: empty string for first round; for subsequent rounds, include the previous critique text AND the user's responses
- `{project_context}`: project summary
- `{code_map_summary}`: if Phase 0.5 produced a code map summary, format it as:
  ```
  ### Codebase Overview

  You have access to the full code map summary for challenging assumptions:

  {the summary text}
  ```
  If Phase 0.5 was skipped or failed, use an empty string (the section is omitted from the prompt).
- `{output_file}`: `01-idea-critique.md`

Append the Handoff Protocol block. Spawn via Agent tool with `subagent_type: "general-purpose"`.

### 2. Present Challenges to User

Read `artifacts/01-idea-critique.md`. Present the key challenges and questions conversationally — don't dump the raw file. Summarize the most important points and ask the user to respond. Use AskUserQuestion for structured input if needed.

### 3. User Response Loop

Collect user responses. For each substantive decision:
- Append a row to `decision-log.md`
- Note which challenge it addresses

### 4. Iterate or Advance

Ask the user: "Do you want another round of idea challenge, or move to detailed planning?"

- **Continue**: Re-spawn Devil's Advocate with updated `{prior_critique}` (previous critique + user responses). Overwrite `artifacts/01-idea-critique.md` with the new analysis.
- **Move on**: Update `status.md` — Phase 1 → completed, Phase 2 → in_progress. Proceed.

---

## Phase 2: Synthesis (Parallel)

**Goal**: Build a comprehensive draft plan from multiple specialist perspectives.

### 1. Prepare Shared Context

Read the current state:
- `artifacts/00-original-idea.md` → `{idea_text}`
- `artifacts/01-idea-critique.md` → `{idea_critique}`
- `decision-log.md` → `{user_decisions}`
- `artifacts/00-seed-document.md` (if it exists) → `{seed_document}`. When present, append the seed document to `{idea_text}` for all synthesis agents with a separator: `\n\n---\n\n## Existing Document (provided by user)\n\n{seed_document_contents}`. This ensures every specialist has access to the user's prior work.

### 2. Spawn Synthesis Agents

Based on the tier, read the appropriate prompt files from `~/.claude/skills/brainstorm/prompts/` and spawn agents.

**All tiers** (always spawn):
- `implementer.md` → Agent writes `artifacts/03-implementation.md`
- `risk-analyst.md` → Agent writes `artifacts/05-risk-assessment.md`

**Feature + System tiers** (also spawn):
- `architect.md` → Agent writes `artifacts/02-architecture.md`
- `domain-expert.md` → Agent writes `artifacts/04-domain-analysis.md`

Fill in template variables for each:
- `{plan_directory}`, `{idea_text}`, `{idea_critique}`, `{user_decisions}`, `{project_context}`, `{tier}`
- `{relevant_files}`: use the role-specific formatted context from Phase 0.5 (e.g., `{relevant_files_architect}` for the architect). If Phase 0.5 was skipped or failed, use an empty string.

Append the Handoff Protocol block to each prompt.

**Spawn all applicable agents in parallel** — use multiple Agent tool calls in a single message. Use `run_in_background: true` for all but the last one so you can process results as they arrive.

### 3. Handle Handoffs

After agents return, check for `artifacts/handoff-*.md` files. If any exist, spawn continuation agents with the handoff context.

### 4. Spawn Synthesis Manager

After ALL synthesis agents have completed, read `~/.claude/skills/brainstorm/prompts/synthesis-manager.md`. Fill in:
- `{plan_directory}`, `{idea_text}`, `{user_decisions}`, `{project_context}`
- `{artifact_list}`: list the artifact files that were created (02 through 05, only those that exist for this tier)

Append the Handoff Protocol. Spawn the Synthesis Manager. It writes `artifacts/06-draft-plan.md`.

### 5. Update State

Update `status.md`: Phase 2 → completed, Phase 3 → in_progress.

---

## Phase 3: User Checkpoint

**Goal**: Get user buy-in before investing in adversarial review.

### 1. Present Draft Plan

Read `artifacts/06-draft-plan.md`. Present a summary to the user covering:
- Proposed approach
- Key architectural decisions (if applicable)
- Implementation steps at a high level
- Top risks identified

### 2. User Decision

Ask the user via AskUserQuestion:
- **Approve**: Proceed to red-team phase.
- **Redirect**: User provides feedback. Append to `decision-log.md`. Determine which synthesis agents need re-running based on the feedback, re-spawn them, then re-run the Synthesis Manager.
- **Kill**: Update `status.md` to set all remaining phases to `abandoned`. Inform the user the brainstorm is archived. Done.

### 3. Update State

Update `status.md`: Phase 3 → completed, Phase 4 → in_progress.

---

## Phase 4: Red-Team (Parallel)

**Goal**: Adversarial review of the draft plan.

### 1. Spawn Red-Team Agents

Read `artifacts/06-draft-plan.md` → `{draft_plan}`.

**All tiers** (always spawn):
- `devils-advocate.md` (with `{mode}`: `plan`, `{output_file}`: `07-assumption-challenge.md`) → `artifacts/07-assumption-challenge.md`
- `scope-auditor.md` → `artifacts/08-scope-audit.md`

**Feature + System tiers** (also spawn):
- `feasibility-checker.md` → `artifacts/09-feasibility-check.md`

Fill in template variables. For Devil's Advocate, include `{code_map_summary}` from Phase 0.5 (formatted as the "Codebase Overview" section, or empty string if Phase 0.5 was skipped). Append the Handoff Protocol. **Spawn all in parallel.**

### 2. Handle Handoffs

Check for handoff files after agents return. Spawn continuations if needed.

### 3. Spawn Review Manager

After ALL red-team agents complete, read `~/.claude/skills/brainstorm/prompts/review-manager.md`. Fill in:
- `{plan_directory}`
- `{artifact_list}`: list of red-team artifact files created (07, 08, 09 — only those that exist)

Append the Handoff Protocol. Spawn. It writes `artifacts/10-review-synthesis.md`.

### 4. Update State

Update `status.md`: Phase 4 → completed, Phase 5 → in_progress.

---

## Phase 5: Reconciliation

**Goal**: Merge the draft plan with red-team findings.

### 1. Spawn Final Arbiter

Read `~/.claude/skills/brainstorm/prompts/final-arbiter.md`. Fill in:
- `{plan_directory}`, `{user_decisions}`, `{project_context}`

Append the Handoff Protocol. Spawn. It writes `artifacts/11-reconciliation.md`.

### 2. Surface Flagged Items

Read `artifacts/11-reconciliation.md`. If it contains items flagged for user decision:
- Present each item with its options and the arbiter's lean
- Collect user decisions via AskUserQuestion
- Append each decision to `decision-log.md`

### 3. Update State

Update `status.md`: Phase 5 → completed, Phase 6 → in_progress.

---

## Phase 6: Final Output

**Goal**: Assemble all artifacts into polished final documents.

### 1. Spawn Output Assembler

Read `~/.claude/skills/brainstorm/prompts/output-assembler.md`. Fill in:
- `{plan_directory}`, `{plan_name}`

Append the Handoff Protocol. Spawn. It writes:
- `plan.md` (in the plan root directory)
- `open-questions.md` (if unresolved items exist)
- Ensures `decision-log.md` is complete

### 2. Final Status Update

Update `status.md`: Phase 6 → completed, all phases → completed.

Present to the user:
- Location of `plan.md`
- Number of open questions (if any)
- One-paragraph summary of the plan
- Suggest: "You can execute this plan with `/conductor` or `/orchestrate`."

---

## Resume Protocol

When `--resume <path>` is provided:

1. Read the `status.md` file at the given path
2. Read `decision-log.md` from the same plan directory
3. Identify the current phase (first non-completed phase in the Phase Progress table)
4. Read all existing artifacts to rebuild context
5. Check for `artifacts/handoff-*.md` files — if any exist, spawn continuation agents first
6. Jump to the appropriate phase section above and continue from where it left off
7. If a phase was `in_progress`, check for partial output files and continue accordingly

---

## Error Handling

- **Agent fails to return or errors**: Check for partial output in the artifact file. If present, spawn a continuation agent with that partial context. If no output, re-spawn the agent.
- **Agent writes empty output**: Re-spawn with additional context or a note to produce output.
- **User kills the brainstorm (Phase 3)**: Update `status.md` phases to `abandoned`. Artifacts remain for reference.
- **Resumption after session end**: `status.md` + artifact files + `decision-log.md` contain all needed state. The resume protocol rebuilds context from files.
- **Handoff detected**: Spawn a continuation agent that reads the handoff file and the partial output file, then completes the work.

---

## Important Notes

- **Stay thin.** You are a dispatcher. Do not do heavy analysis yourself. Spawn agents for all substantive work.
- **Files are truth.** Always read state from files before making decisions. Never rely on conversation memory.
- **Update status.md after every phase transition.** This is your compaction resilience guarantee.
- **Parallel where possible.** Synthesis agents are independent — spawn them in parallel. Red-team agents are independent — spawn them in parallel. Managers depend on workers — spawn sequentially after workers complete.
- **User interaction is your job.** Agents write to files. You read those files and present findings conversationally to the user. Don't dump raw file contents — summarize, highlight, and ask targeted questions.
