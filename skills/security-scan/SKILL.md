---
name: security-scan
description: On-demand security audit — OWASP Top 10, dependency CVEs, secrets detection, and static analysis across the current project or specified files.
argument-hint: [path/to/dir-or-file] [--deps-only] [--no-deps] [--fix]
allowed-tools: Agent, Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion
---

# Security Scan

Run a multi-pass security audit on the current project or a specified path.

## Argument Parsing

Parse `$ARGUMENTS`:
- **Path** (optional): file or directory to scope the scan. Defaults to current working directory.
- `--deps-only`: only check dependencies for known CVEs, skip code analysis.
- `--no-deps`: skip dependency checks, only scan code.
- `--fix`: after reporting findings, apply safe fixes automatically (secrets removal, dependency upgrades, injection fixes). Dangerous fixes (auth changes, crypto changes) are presented for user approval.

## Phase 1: Project Discovery

1. Identify the project type by looking for manifest files:
   - `package.json` / `package-lock.json` / `pnpm-lock.yaml` → Node.js
   - `requirements.txt` / `pyproject.toml` / `Pipfile.lock` → Python
   - `go.mod` → Go
   - `Cargo.toml` → Rust
   - `Gemfile.lock` → Ruby
   - Multiple manifests → multi-language project, scan all
2. Identify the framework (Express, FastAPI, Next.js, Django, etc.) from imports and config.
3. Note the scan scope for Phase 2 agents.

## Phase 2: Parallel Scan Agents

Spawn the following agents in parallel. Each writes findings to a structured format.

### Agent 1: OWASP Code Analysis

```
You are a security auditor performing static analysis against the OWASP Top 10.

Project path: {path}
Framework: {framework}
Languages: {languages}

Scan all source files for these vulnerability classes:

1. **Injection** (SQL, NoSQL, command, LDAP, XPath)
   - String concatenation in queries
   - Unparameterized queries
   - Shell command construction from user input
   - Template injection

2. **Broken Authentication**
   - Hardcoded credentials or tokens
   - Weak password validation
   - Missing rate limiting on auth endpoints
   - Session fixation risks

3. **Sensitive Data Exposure**
   - Secrets in source code (API keys, tokens, passwords)
   - Sensitive data in logs or error messages
   - Missing encryption for PII
   - Overly verbose error responses

4. **XXE / Insecure Deserialization**
   - XML parsing without disabling external entities
   - Unsafe deserialization (pickle, yaml.load, eval, JSON.parse on untrusted input)

5. **Broken Access Control**
   - Missing authorization checks on endpoints
   - IDOR patterns (user IDs in URLs without ownership checks)
   - Directory traversal in file operations
   - CORS misconfiguration

6. **Security Misconfiguration**
   - Debug mode enabled
   - Default credentials
   - Missing security headers
   - Overly permissive CORS
   - Exposed stack traces

7. **XSS**
   - Unescaped user input in HTML/templates
   - dangerouslySetInnerHTML or equivalent
   - DOM manipulation with user data

8. **CSRF**
   - State-changing endpoints without CSRF tokens
   - Missing SameSite cookie attributes

9. **Known Vulnerable Components** (handled by Agent 2)

10. **Insufficient Logging**
    - Auth events not logged
    - No audit trail for sensitive operations

For each finding, report:
- **Severity**: CRITICAL / HIGH / MEDIUM / LOW
- **File**: path and line number
- **Vulnerability**: which OWASP category
- **Code**: the problematic code snippet
- **Risk**: what an attacker could do
- **Fix**: specific remediation
```

### Agent 2: Dependency Audit (skip if `--no-deps`)

```
You are a dependency security auditor.

Project path: {path}
Package manager(s): {detected managers}

1. Run the appropriate audit command(s):
   - npm/pnpm: `npm audit --json` or `pnpm audit --json`
   - pip: `pip audit --format=json` (if available) or check against known CVE databases
   - Go: `go vuln check` (if available)
   - Check for outdated packages with known security issues

2. If audit tools aren't installed, manually check:
   - Read lock files for exact versions
   - Flag packages with known critical CVEs based on your knowledge
   - Flag wildcard or overly broad version ranges

3. Check for:
   - Packages with no recent maintenance (potential supply chain risk)
   - Packages pulled from unusual registries
   - Postinstall scripts that do suspicious things

For each finding report: package name, installed version, CVE ID if known, severity, and recommended version.
```

### Agent 3: Secrets Detection

```
You are a secrets scanner.

Project path: {path}

Scan ALL files (including config, scripts, docs, and dotfiles) for:

1. **API keys and tokens**: AWS, GCP, Azure, Stripe, Twilio, SendGrid, OpenAI, Anthropic, GitHub, etc.
   - Match patterns: sk-..., AKIA..., ghp_..., sk-ant-..., etc.
2. **Passwords and credentials**: hardcoded in source, config, or env files checked into git
3. **Private keys**: RSA, SSH, PGP key material in files
4. **Connection strings**: database URLs with embedded passwords
5. **JWT secrets**: hardcoded signing keys
6. **.env files**: check if .env is in .gitignore. If not, flag as CRITICAL.

Also check:
- Git history (last 20 commits) for secrets that were added then removed — they're still in history
  Run: git log --all -p --diff-filter=D -20 and git log --all -p -20 scanning for secret patterns
- .gitignore coverage: are .env, credentials, key files properly excluded?

For each finding: severity, file, line, secret type, and whether it's in current files or git history.
```

## Phase 3: Synthesize Report

After all agents return, compile findings into a single report sorted by severity.

### Report Format

```
## Security Scan Report

**Project**: {path}
**Date**: {date}
**Scope**: {what was scanned}

### Summary

| Severity | Count |
|----------|-------|
| CRITICAL | {n}   |
| HIGH     | {n}   |
| MEDIUM   | {n}   |
| LOW      | {n}   |

### Critical Findings
{each finding with full details}

### High Findings
{each finding}

### Medium Findings
{each finding}

### Low Findings
{each finding}

### Dependency Issues
{audit results}

### Recommendations
{prioritized action items}
```

Present the report to the user. If there are CRITICAL or HIGH findings, emphasize them.

## Phase 4: Auto-Fix (only if `--fix`)

For each finding, classify the fix safety:

| Safe to auto-fix | Requires approval |
|---|---|
| Remove hardcoded secrets (replace with env var references) | Auth logic changes |
| Add .env to .gitignore | Cryptographic changes |
| Upgrade dependencies to patched versions | Access control changes |
| Add parameterized queries (clear cases) | Architecture changes |
| Add input sanitization | Removing functionality |
| Add security headers |  |

Apply safe fixes directly. For fixes requiring approval, present each one to the user via AskUserQuestion with the risk and proposed change.

After all fixes, re-run the relevant scan agents to confirm the fixes resolved the issues. Report the before/after.

## Rules

- Never log, print, or display actual secret values in findings — show only the type and location.
- Do not commit or push anything. Leave that to the user.
- If no issues are found, say so clearly — don't manufacture findings.
- When in doubt about severity, err on the side of higher severity.

Usage: `/security-scan` to scan the whole project, or `/security-scan src/api --fix` to scan and fix a specific path.
