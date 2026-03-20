# Context Selection Protocol (Reference Documentation)

This document describes the auto-context selection protocol used in Phase 0.5 of the brainstorm skill. This is NOT an agent prompt — the selection is performed by the code map CLI, not by an agent.

## Purpose

Phase 0.5 pre-selects relevant code files for each specialist role so they receive targeted context instead of needing to explore the codebase independently. This reduces redundant file exploration across agents and focuses each specialist on the files most relevant to their analysis.

## When It Runs

Phase 0.5 runs between Phase 0 (Setup & Triage) and Phase 1 (Idea Challenge) for code projects only.

### Skip Conditions

Phase 0.5 is skipped entirely when:
- The project is not a code project (no recognized project manifest files)
- No project directory was detected during Phase 0
- No code map cache exists AND the project contains 100+ files

When skipped, all context variables (`{relevant_files}`, `{code_map_summary}`) are set to empty strings. The specialist prompts are designed to handle empty context gracefully — they fall back to manual codebase exploration.

## CLI Commands

### Generate/Update Code Map

```bash
$CODEMAP_CMD {project_path}
```

Generates or updates the cached code map for the project.

### Get Code Map Summary

```bash
$CODEMAP_CMD {project_path} --summary
```

Returns a high-level summary of the codebase structure. Used as `{code_map_summary}` for the Devil's Advocate role.

### Select Files for Roles

```bash
$CODEMAP_CMD {project_path} --select-for-roles '{"idea": "{idea_text}", "roles": ["architect", "implementer", "risk-analyst", "domain-expert"]}' --json
```

Returns a JSON object mapping each role to its list of relevant file paths:

```json
{
  "architect": ["src/core/engine.py", "src/api/routes.py"],
  "implementer": ["src/models/user.py", "tests/test_user.py"],
  "risk-analyst": ["src/auth/handler.py", "src/db/migrations/"],
  "domain-expert": ["src/domain/rules.py", "src/workflows/checkout.py"]
}
```

## Role Selection Criteria

Each role receives files selected based on different relevance criteria:

### Architect
Files relevant to system structure, boundaries, data flow, and integration points:
- Configuration files, entry points, module boundaries
- API definitions, interface contracts
- Existing architecture patterns and conventions

### Implementer
Files that would need modification or serve as implementation patterns:
- Files directly affected by the proposed change
- Test files and test patterns
- Similar existing implementations to use as templates

### Risk Analyst
Files with security, performance, or reliability implications:
- Authentication/authorization code
- Database queries and data access patterns
- Error handling, logging, monitoring
- External service integrations

### Domain Expert
Files containing business logic, user workflows, and domain rules:
- Domain model definitions
- Business rule implementations
- User-facing workflow code
- Validation and constraint logic

## Output Artifact

The selection results are saved to `{plan_directory}/artifacts/00-context-selection.json`:

```json
{
  "timestamp": "2026-03-15T12:00:00Z",
  "project_path": "/path/to/project",
  "idea_text": "the original idea",
  "selection": {
    "architect": ["file1.py", "file2.py"],
    "implementer": ["file3.py"],
    "risk-analyst": ["file4.py"],
    "domain-expert": ["file5.py"]
  },
  "code_map_summary_length": 2450
}
```

This artifact is saved for debugging and review purposes.

## Formatting for Specialist Prompts

Selected files are read and formatted as markdown blocks injected into the `{relevant_files}` template variable:

```markdown
### Pre-Selected Code Context

The following files have been identified as relevant to your analysis. You do NOT
need to explore the codebase — this context has been pre-selected for your role.

#### `path/to/file.py`
\```python
{file contents}
\```
```

When `{relevant_files}` is empty (Phase 0.5 was skipped or failed), this section is omitted entirely from the prompt. The specialist prompts detect the absence and fall back to standard codebase exploration.

## Devil's Advocate: Code Map Summary

The Devil's Advocate role receives the full code map summary instead of per-file selections. This gives it a broad view of the codebase for challenging assumptions about scope, complexity, and integration:

```markdown
### Codebase Overview

You have access to the full code map summary for challenging assumptions:

{code_map_summary}
```

When `{code_map_summary}` is empty, this section is omitted.

## Error Handling

Phase 0.5 is designed to be non-blocking:

1. If the code map generator fails (non-zero exit), the error is logged and Phase 0.5 is skipped
2. If the context selector fails, all `{relevant_files}` are set to empty strings
3. If individual file reads fail during formatting, those files are skipped with a note
4. No Phase 0.5 failure prevents the brainstorm from proceeding to Phase 1
