---
name: catch-me-up
description: >
  Quickly orients the user in any project after a break. Use this whenever the user says things like "catch me up", "what was I working on", "what's going on in this project", "where did I leave off", "status check", "remind me what I was doing", or opens a project cold and needs context. Works on any codebase — no project-specific knowledge required. Scans git history, recent changes, and key files, then dumps a single markdown summary. Trigger proactively if the user seems disoriented or is asking broad questions about their own codebase.
---

# Catch Me Up

Orient the user in their current project. Run a quick scan (target: under 30 seconds) and produce a single markdown summary. Do not ask questions. Do not wait for permission. Scan and dump.

## Scan sequence

Run these in order using the Bash tool. If a command fails (e.g. not a git repo), note it briefly and move on.

**1. Git orientation**
```bash
git branch --show-current
git status --short
git log --oneline -8
git stash list
```

**2. Recent activity** — what changed across the last few commits
```bash
git diff --name-only HEAD~3..HEAD 2>/dev/null
git log --oneline --since="7 days ago" 2>/dev/null
```

**3. Project structure** — top level only
```bash
ls -1
```

**4. In-progress markers** — TODOs/WIP in recent diffs
```bash
git diff HEAD~1 2>/dev/null | grep -i "TODO\|FIXME\|WIP\|HACK\|XXX" | head -10
```

**5. Key project file** — pick ONE and skim it (first 40 lines max):
`CLAUDE.md` → `README.md` → `package.json` → `pyproject.toml` → `Cargo.toml` → whichever exists first. Use it only to confirm what the project is — don't over-read.

## Output format

Write a markdown summary with exactly these sections. The whole thing should be skimmable in 30 seconds.

```markdown
# Project Status

**Branch:** `<branch-name>`
**Last commit:** `<hash>` — <message> (<relative time, e.g. "2 days ago">)

## What changed recently
- <specific file or files> — <what kind of change: added, refactored, fixed, wired up, etc.>
- ...

## Where things stand
<2–4 sentences. What is actively being worked on? Look at uncommitted changes, stash entries, recent commit topics, and TODO markers. Be specific — name files, features, or subsystems. Infer confidently.>

## Next logical step
<One sentence. Your best inference about what needs to happen next, based on the evidence.>

## Quick vitals
- Uncommitted changes: <yes — N files / no>
- Stashed work: <yes — N entries / no>
- Branch vs remote: <ahead N / behind N / up-to-date / no remote tracked>
```

## Tone rules

- Be specific. "Modified `backend/app/routes/posts.py`" beats "some backend files."
- Infer confidently. If the last 3 commits all touch auth and there's a half-finished TODO in `security.py`, say so directly.
- One sentence of uncertainty is fine. More is noise.
- Do not narrate your scanning process. Output only the final markdown summary.
