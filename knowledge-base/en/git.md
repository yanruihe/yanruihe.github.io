# Git Knowledge Base

## How Git saves and uploads changes

Suppose you edit `README.md`. The file is not automatically uploaded to GitHub. It moves through four steps:

1. **Working tree**: you edit the file on your computer; the change is not yet a Git commit.
2. **Staging area**: `git add README.md` selects the content for the next commit.
3. **Local repository**: `git commit -m "docs: update README"` records a commit on your computer.
4. **Remote repository**: `git push` uploads the commit to GitHub.

```bash
git status
git add README.md
git commit -m "docs: update README"
git push
```

Use `git status` to see what changed and what is staged. `git add` does not create a commit, and `git commit` does not upload it. For the first push of a new branch, use `git push -u origin HEAD`.

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
