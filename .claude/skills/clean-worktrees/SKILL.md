---
name: clean-worktrees
description: |
  Find and clean up stale git worktrees. Categorizes each as safe-to-remove
  (clean, zero commits ahead, commits already merged under a different SHA, or
  branch already backing an open PR) vs needs-review (real unmerged work).
  Handles common gotchas: misleading admin-dir mtimes, branches silently backing
  PRs, squash-merged commits, noise in the dirty-file list.
  Use when asked to "clean up worktrees", "find orphan worktrees", "prune
  worktrees", or when stale worktree directories pile up.
---

# clean-worktrees

A careful, repeatable process for cleaning up the pile of worktree directories that accumulates when agents, IDE tools, or humans forget to tear them down.

## When to invoke

- User asks to clean up, prune, or find orphan worktrees.
- User points at a folder full of `worktree-*`, `agent-*`, or randomly-named directories.
- You notice many stale worktrees while working on something else.

## Philosophy

**Never assume a worktree is orphaned.** The work on it may be:

- Already merged under a different SHA. Squash and rebase merges rewrite commit hashes, so the original commits look unmerged to `git log`, but the change is on the base branch under a new SHA.
- Already pushed and backing an open PR you haven't seen yet.
- Untracked but meaningful — planning docs, scratch notes, or experiments the user wants to keep.

Local worktree removal is recoverable via reflog for ~30 days. But closing a PR and deleting its remote branch is painful to undo. **Verify before deleting, and present evidence before bulk actions.**

## Process

### 1. Decide scope

Ask the user if it isn't obvious. Common scopes:

- A single repo.
- All repos under a given folder (e.g. their main projects directory).
- All repos a specific tool creates worktrees for.

### 2. Discover worktree directories

Worktrees live in many places. Combine these sources:

```bash
# (a) Authoritative per-repo list. This catches everything git itself knows about.
git -C <repo> worktree list

# (b) Directories that look like worktrees but git doesn't know about them —
# find the .git pointer file and follow it to the owning repo.
find <search-root> -maxdepth 4 -name .git -type f 2>/dev/null \
  | while read f; do echo "$(dirname "$f")  →  $(cat "$f")"; done
```

Typical places they hide:

- Sibling directories to the owning repo (when a tool creates top-level worktrees).
- Inside the repo under conventions like `.claude/worktrees/` or similar.
- A centralized root the tool uses (`~/worktrees/`, `~/.<tool>-worktrees/`, `/tmp/`).
- Temp locations like `/tmp/` or `/private/tmp/` (survive reboots on some systems, not others).

Cross-reference `git worktree list` output (which may list directories that no longer exist — `prunable`) with actual directories on disk (which may include ones git has forgotten about — check the `.git` pointer).

### 3. Inspect each worktree

For each one, gather:

```bash
W=<worktree-path>
# Detect the base branch dynamically — don't hardcode "main"
BASE=$(git -C "$W" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
       | sed 's|refs/remotes/||')

git -C "$W" rev-parse --abbrev-ref HEAD        # current branch
git -C "$W" rev-list --count HEAD "^$BASE"     # commits ahead of base
git -C "$W" status --porcelain                  # dirty state
# mtime of the worktree dir (see gotcha #1 — don't use the admin dir mtime)
stat -f '%Sm' "$W" 2>/dev/null || stat -c '%y' "$W"
```

**Filter dirty-state noise** before treating a worktree as "has changes". Noise categories that are almost always safe to ignore:

- Dev server / build output files not in `.gitignore` (e.g. `*.log`, `.cache/`).
- Submodule pointer drift (` M <submodule>`) when some worktrees ran submodule-updating commands and others didn't.
- Editor and OS cruft (`.DS_Store`, `Thumbs.db`, swap files, `.idea/`).

If the same "dirty" pattern appears across many worktrees, it's noise. When unsure, show the user one example and ask.

### 4. Verify "unmerged" commits are actually unmerged

A commit ahead of base may still be merged under a different SHA (squash or rebase merge). Check by matching commit subject:

```bash
msg=$(git -C "$W" log -1 --format=%s HEAD)
# Escape regex metacharacters in the subject before passing to --grep
git -C <repo> log --oneline --all \
  --grep="$(printf '%s' "$msg" | sed 's/[][\\^$.*]/\\&/g')"
```

If the same subject appears on the base branch with a different SHA (often with a `(#123)` PR suffix), the commit was squash-merged. Treat as merged.

### 5. Check whether the branch already backs a PR

The single most important check before creating new PRs or deleting branches:

```bash
OWNER_REPO=$(git -C <repo> config --get remote.origin.url \
  | sed -E 's|.*[:/]([^/]+/[^/.]+)(\.git)?$|\1|')
BRANCH=$(git -C "$W" rev-parse --abbrev-ref HEAD)
gh -R "$OWNER_REPO" pr list --state all --search "head:$BRANCH" \
  --json number,title,state,url
```

(Requires `gh` authenticated; fall back to asking the user to check if it isn't installed.)

If an open PR exists:

- **Do not** create a new PR from the same branch — you'll make a duplicate.
- **Do not** force-push to rebase without explicit user permission — reviewers may be mid-review.
- Removing the local worktree is still fine; the work is safe on origin.

### 6. Categorize and present

Group the worktrees into a table the user can skim. Suggested categories:

| Category | Criteria | Default action |
|---|---|---|
| **Safe** | 0 ahead AND no real dirty state (after filtering noise) | Remove |
| **Already merged** | Commits match a base-branch commit by subject | Remove |
| **Backed by open PR** | `gh pr list` finds an open PR on the branch | Remove local worktree only; leave remote + PR untouched |
| **Needs review** | Real unmerged commits with no matching PR, or non-noise untracked files | Ask user: abandon, push + open PR, or leave for later |

Present with evidence (PR numbers, commit SHAs, file lists) so the user can decide per category. Do not bulk-delete across categories without confirmation.

### 7. Clean up safely

Order matters — a branch can't be deleted while a worktree holds it, and the admin entry sticks around until pruned:

```bash
git -C <repo> worktree remove --force <path>   # --force tolerates untracked noise
git -C <repo> branch -D <branch>                # fails if still checked out elsewhere
git -C <repo> worktree prune -v                 # removes stale admin entries
# Only if the user explicitly confirms deleting the remote too:
git -C <repo> push origin --delete <branch>
```

Before any destructive step, print the SHA so the user can recover via reflog:

```bash
echo "<branch>: $(git -C <repo> rev-parse <branch>)"
```

## Gotchas

1. **Admin dir mtimes (`.git/worktrees/<name>/`) are misleading.** `git status`, `git worktree list`, and even `git fetch` touch those mtimes. To see when a worktree was really last worked on, `stat` the worktree directory itself, not the admin dir. Getting this wrong once made a batch of 16-day-old worktrees look one-minute-old and nearly caused a panic.

2. **Zsh reserves `$status`.** `for w in ...; do local status=$(...); done` fails with "read-only variable: status". Use any other name.

3. **Tool-created worktree branches often have a predictable prefix** (e.g. `worktree-*`, `agent-*`). These are hints about *origin*, not *safety*. A branch with such a prefix may still have real commits — always check before removing.

4. **Pushes during a failed rebase can leak pre-rebase state.** If you chain `git rebase && git push` and the rebase fails mid-way, the shell may still run the push, publishing the un-rebased branch. Check `git status` between rebase and push, or use `set -e` / `&&` carefully.

5. **A closed PR with a deleted branch cannot be reopened.** GitHub requires the branch to exist. If there's any chance the user might revive the PR, close it but leave the branch until they confirm.

6. **Multiple top-level worktrees with similar names usually share one owning repo.** Group them via the `.git` pointer file before scanning — don't re-run expensive checks per directory when they all point at the same repo.

7. **`worktree remove --force` does not delete the branch.** It removes the directory and admin entry only. The branch deletion is a separate `branch -D`.

8. **Base branch isn't always `main`.** Detect it from `refs/remotes/origin/HEAD`. Never hardcode, especially when scanning multiple repos.

## Portability notes

- `stat` flags differ between BSD (macOS) and GNU (Linux). Use the fallback chain above.
- `gh` is the path of least resistance for PR checks; without it, fall back to asking the user.
- Nothing in this skill assumes a specific project, tool, or directory layout — it's driven by what `git` and `gh` report.
