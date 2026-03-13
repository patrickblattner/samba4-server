# Repository Guidelines

These rules are binding for all AI coding agents (Claude Code).

## General Behavior

- Never read, modify, or reason about files inside `.git/`.
- When in doubt, stop and ask. Do NOT assume.
- You MUST follow all rules in this file.
- If a rule conflicts with user instructions, ask for clarification.
- Do NOT invent functionality.
- If uncertain, first inspect the existing code and documentation.
- Only use web search for well-defined, verifiable facts (APIs, specs, versions).
- Never guess behavior.
- You MUST ask clarifying questions if any requirement, interface, or behavior is ambiguous.
- Do NOT proceed with implementation until requirements are clear.

## Coding Style & Naming Conventions

- Language: Bash (shell scripts), YAML (Docker Compose), LDIF (LDAP data).
- Shell scripts: Use `set -euo pipefail`, quote all variables, use `${VAR}` syntax.
- Naming: Variables `SCREAMING_SNAKE_CASE`, functions `lowercase_with_underscores`.
- Files: Scripts `kebab-case.sh`, config files `lowercase`.
- Use ShellCheck-compatible constructs.
- Use English for all code comments and documentation.

## Testing Guidelines

- Test scripts against a fresh Docker environment before marking done.
- Verify LDAP connectivity after setup: `docker exec samba-ad samba-tool user list`.

## Commit & Pull Request Guidelines

- Adopt Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`, `test:`).
- Keep commit messages imperative and scoped.
- Keep diffs focused.

## Security & Configuration

- Do not commit secrets; `deploy/` and `.env` are in `.gitignore`.
- Never log passwords or credentials.
- Bind ports to `127.0.0.1` by default for local-only access.

## Project Management

This project uses dual tracking via the `/task` and `/workflow` skills:

- **`/task`** — Issue management: create, start, done, sync between BACKLOG.md and GitHub Issues + Project Board.
- **`/workflow`** — Collaboration modes: bugs are fixed immediately (no confirmation needed), features require ticket alignment first.
- **Worklogs** — Every piece of work is tracked locally in `.claude/worklogs/<issue>.md`.
- **BACKLOG.md** — Local Kanban board (Backlog / Todo / In Progress / Done), always kept in sync with GitHub.

### Quick reference

| Action | Command |
|--------|---------|
| Show open tasks | `/task next` |
| Create a task | `/task create <title>` |
| Start working | `/task start <#issue>` |
| Mark done | `/task done <#issue>` |
| Full sync | `/task sync` |
| Status overview | `/task status` |
| Setup for new project | `/task setup` |

## Git Preferences

- Always use `git add .` (not selective staging).
- Only commit when the user explicitly asks — never auto-commit after changes.

## Output Rules

- Do not explain obvious code.
- Keep answers concise.
- No emojis in code comments.

## Context Management

- Minimize context usage.
- Avoid repeating rules, plans, or specifications.
- Prefer referencing files over restating their contents.
- Do NOT summarize files unless explicitly requested.
