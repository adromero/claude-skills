# Claude Skills

A collection of multi-agent skills and agents for [Claude Code](https://code.claude.com). These extend Claude Code with sophisticated planning, building, debugging, and security workflows.

## Skills

### `/brainstorm` — Multi-Agent Plan Synthesis
Turn an idea into a rigorous implementation plan through 6 phases:

1. **Setup & Triage** — classify scope (patch / feature / system), detect project context
2. **Idea Challenge** — Devil's Advocate stress-tests your idea before you invest in planning
3. **Synthesis** — parallel specialist agents (Architect, Implementer, Domain Expert, Risk Analyst) produce a draft plan
4. **User Checkpoint** — review and redirect before adversarial review
5. **Red-Team** — Devil's Advocate, Scope Auditor, and Feasibility Checker attack the draft
6. **Reconciliation & Output** — merge findings into a polished `plan.md`

Supports seed documents (existing PRDs, RFCs, architecture docs), resume across sessions, and optional code map integration for targeted context.

### `/conductor` — Multi-Agent Build Conductor
Execute implementation plans produced by `/brainstorm` (or any structured markdown plan) using parallel worker agents:

- Parses plans into a dependency graph of stages
- Dispatches worker agents with stage specs, verification agents confirm results
- Retries failed stages up to 3x with error context
- Auto-chains across context windows for long builds
- File-based state (`progress.json`) — resume anytime with `--resume`

Flags: `--dry-run`, `--stage=X`, `--skip=X`, `--max-workers=N`, `--no-codemap`

### `/review-plan` — Plan Reviewer
Launches an independent Opus reviewer agent to critically assess any plan against 6 criteria:

- Goal Alignment, Feasibility, Red-Teaming, Simplicity, Completeness, Security
- Structured PASS/WARN/FAIL ratings with evidence
- Works standalone (`/review-plan path/to/plan.md`) or inline during plan mode

### `/tdd-fix` — TDD Bug Fix with Smart Routing
Fix bugs using test-driven development with automatic domain classification:

- Classifies bugs across domains: frontend, backend, database, infra
- Single-domain bugs: linear TDD flow (failing test → fix → green suite)
- Cross-cutting bugs: spawns parallel specialist agents per domain, synthesizes findings, then applies TDD
- Never skips or disables existing tests

### `/security-scan` — Security Audit
On-demand security audit with three parallel scan agents:

- **OWASP Code Analysis** — all Top 10 categories, framework-aware static analysis
- **Dependency Audit** — CVE scanning via `npm audit` / `pip audit` / etc.
- **Secrets Detection** — pattern matching in source + git history scanning

Supports `--fix` for auto-remediation (safe fixes applied directly, dangerous ones need approval), `--deps-only`, `--no-deps`.

### `/verify` — Verify Fix
Lightweight post-fix verification — run affected tests and check for regressions.

## Agents

Supporting agents used by the skills above:

| Agent | Used By | Purpose |
|-------|---------|---------|
| `build-worker.md` | `/conductor` | Executes stage deliverables with write-ahead logging |
| `build-verifier.md` | `/conductor` | Read-only verification of completed stages |
| `architecture-planner.md` | Standalone | Multi-session project planning with task breakdown |

## Installation

```bash
git clone https://github.com/adromero/claude-skills.git
cd claude-skills
./install.sh
```

This copies skills to `~/.claude/skills/` and agents to `~/.claude/agents/`.

Or manually copy individual skills:

```bash
cp -r skills/brainstorm ~/.claude/skills/
cp -r skills/conductor ~/.claude/skills/
cp agents/build-worker.md ~/.claude/agents/
cp agents/build-verifier.md ~/.claude/agents/
```

## Code Map Integration (Optional)

`/brainstorm` and `/conductor` can optionally use a code map generator to pre-select relevant files for each agent, reducing redundant codebase exploration.

### Setup

1. Install a code map generator that supports this CLI interface:

   ```bash
   # Generate/update code map for a project
   $CODEMAP_CMD <project_path>

   # Get a high-level codebase summary
   $CODEMAP_CMD <project_path> --summary

   # Select relevant files for specific roles (brainstorm)
   $CODEMAP_CMD <project_path> --select-for-roles '{"idea": "...", "roles": ["architect", ...]}' --json

   # Select relevant files for a description (conductor)
   $CODEMAP_CMD <project_path> --select "<description>" --json

   # Incrementally update after file changes (conductor)
   $CODEMAP_CMD <project_path> --update-files file1.py file2.py
   ```

2. Set `CODEMAP_CMD` in your Claude Code settings:

   ```json
   {
     "env": {
       "CODEMAP_CMD": "bash /path/to/your/code-map-generator/run.sh"
     }
   }
   ```

### Without Code Map

Everything works without it. `/brainstorm` skips Phase 0.5 (auto-context selection) and agents fall back to manual codebase exploration. `/conductor` accepts `--no-codemap` explicitly, or gracefully degrades if the command isn't available.

## How It All Fits Together

```
Idea → /brainstorm → plan.md → /conductor → built project
                ↓                    ↓
          /review-plan          /verify
                                /tdd-fix
                                /security-scan
```

1. Start with `/brainstorm` to plan
2. Optionally `/review-plan` to stress-test the plan
3. `/conductor plan.md` to build
4. `/verify` and `/tdd-fix` for bug fixes
5. `/security-scan` before shipping

## License

MIT
