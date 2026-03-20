---
name: tdd-fix
description: Fix a bug using TDD with smart agent routing — classifies the issue domain and dispatches specialist agents for cross-cutting bugs.
argument-hint: <bug description>
allowed-tools: Agent, Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion
---

## TDD Bug Fix

Fix a bug using test-driven development. The user will describe the bug after invoking this skill.

### Step 0: Classify the Bug Domain

Before diving in, read the relevant code and classify which domains the bug touches:

| Domain | Signals |
|--------|---------|
| **frontend** | UI components, CSS, browser APIs, React/Vue/Svelte state, rendering |
| **backend** | API routes, middleware, server logic, auth, sessions |
| **database** | Queries, migrations, schema, ORMs, data integrity |
| **infra** | Config, env vars, build tooling, deployment, Docker, networking |

- **Single domain** → handle it yourself in the steps below.
- **Cross-cutting (2+ domains)** → spawn a specialist Agent per domain in parallel. Each agent investigates its domain, identifies the root cause contribution, and reports back. Then synthesize their findings before proceeding to Step 2.

#### Cross-cutting dispatch

For each affected domain, spawn an Agent with:

```
You are a {domain} specialist investigating a bug.

Bug description: {user's bug description}

Your task:
1. Read the relevant {domain} code
2. Identify what's broken or misconfigured in your domain
3. Determine if the root cause is in your domain or if another domain is the upstream trigger
4. Report: root cause analysis, affected files, and your recommended fix

Be concise. Write findings only — do not make changes.
```

After all specialists return, synthesize: identify the true root cause, determine the fix order (e.g., fix DB schema before backend code), and proceed.

### Step 1: Understand the Bug

Read the relevant code and reproduce the issue mentally. Ask clarifying questions only if the description is ambiguous. If cross-cutting agents ran, incorporate their findings.

### Step 2: Write a Failing Test First

Create a test that captures the exact broken behavior described. Run the test suite to confirm it fails for the right reason.

### Step 3: Fix the Code

Make the minimal change needed to fix the bug. Do not refactor unrelated code. For cross-cutting bugs, fix in dependency order (infra → database → backend → frontend).

### Step 4: Run the Full Test Suite

If the new test passes but others break, fix those too. Repeat until the entire suite is green.

### Step 5: Summarize

Show a concise summary of:
- The root cause (and which domain(s) it spanned)
- The failing test added (file and test name)
- The fix applied (files changed and why)
- Any secondary fixes needed to keep the suite green

### Rules
- Never skip or disable existing tests to make the suite pass.
- If the project has no test infrastructure, set it up minimally before proceeding.
- Commit nothing — leave that to the user.

Usage: `/tdd-fix` then describe the bug
