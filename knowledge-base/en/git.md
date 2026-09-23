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
git commit -m "docs: update yocto notes"
git fetch origin
git rebase origin/main
git push -u origin HEAD
```

Use short-lived branches for features or knowledge topics. Rebase unpublished commits when tidying history; do not rewrite commits that others already depend on.

## Safe recovery

```bash
git restore -- path/to/file
git restore --staged -- path/to/file
git revert <commit>
git reflog
```

Prefer `revert` for public branch corrections. Keep Yocto layer and recipe changes in focused commits and record the machine, image, layer version, and verification command.

References: [Git branches](https://git-scm.com/docs/git-branch), [Git rebase](https://git-scm.com/docs/git-rebase), and [Git pull](https://git-scm.com/docs/git-pull).
