# Git Knowledge Base

## Mental model

Git work is easiest to reason about as four areas: working tree, staging area, local repository, and remote repository.

```text
Working tree --git add--> Staging area --git commit--> Local repo --git push--> Remote repo
```

## Daily workflow

```bash
git switch main
git pull --ff-only origin main
git switch -c feature/short-description
git status
git diff --check
git add -p
git commit -m "docs: update git notes"
git fetch origin
git rebase origin/main
git push -u origin HEAD
```

Use short-lived branches for features or knowledge topics, such as `feature/logging`. Rebase unpublished commits when tidying history; do not rewrite commits that others already depend on.

## Safe recovery

```bash
git restore -- path/to/file
git restore --staged -- path/to/file
git revert <commit>
git reflog
```

Prefer `revert` for public branch corrections.

## Commit and review conventions

- Keep each commit focused on one logical change so it is easy to understand, review, and revert.
- Use a short prefix for the type and scope, for example `docs(git): clarify restore examples`.
- Review the complete diff and check for secrets, temporary files, or unrelated changes before committing.
- Record review feedback and verification results before merging; add a clear follow-up commit when changes are needed.

## Publish to a remote repository

```bash
git fetch origin
git switch main
git pull --ff-only origin main
git switch -c docs/update-git-notes
# Edit Git documentation or related files
git diff --check
git add path/to/changed-files
git commit -m "docs(git): update workflow notes"
git push -u origin HEAD
```

References: [Git branches](https://git-scm.com/docs/git-branch), [Git rebase](https://git-scm.com/docs/git-rebase), and [Git pull](https://git-scm.com/docs/git-pull).
