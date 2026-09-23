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

## 6. Practical example: commit only the intended change

Suppose `README.md` and a local configuration file have changed, but only the documentation belongs in this commit:

```bash
git status -sb
git diff -- README.md
git add README.md
git diff --cached
git diff --cached --check
git commit -m "docs: clarify setup steps"
```

If you staged the wrong file, run `git restore --staged -- README.md`; the working-tree edit remains. Use `git add -p` to select individual hunks.

## 7. Two-person collaboration demo: branch, review, merge, sync

Run this in PowerShell. It creates a temporary bare remote and two independent clones for Alice and Bob, leaving real repositories untouched.

### 7.1 Create a temporary remote and two clones

```powershell
$demoRoot = Join-Path $env:TEMP ("git-team-demo-" + [guid]::NewGuid().ToString("N"))
$remote = Join-Path $demoRoot "remote.git"
$alice = Join-Path $demoRoot "alice"
$bob = Join-Path $demoRoot "bob"
New-Item -ItemType Directory -Path $demoRoot | Out-Null
git init --bare $remote
git --git-dir=$remote symbolic-ref HEAD refs/heads/main
git clone $remote $alice
git -C $alice config user.name Alice
git -C $alice config user.email alice@example.test
Set-Content (Join-Path $alice "README.md") "Team notes"
git -C $alice add README.md
git -C $alice commit -m "docs: start team notes"
git -C $alice push -u origin main
git clone $remote $bob
git -C $bob config user.name Bob
git -C $bob config user.email bob@example.test
```

### 7.2 Alice proposes a branch; Bob reviews and merges

```powershell
git -C $alice switch -c docs/add-workflow
Add-Content (Join-Path $alice "README.md") "Review changes before merging."
git -C $alice add README.md
git -C $alice commit -m "docs: add review workflow"
git -C $alice push -u origin docs/add-workflow

git -C $bob fetch origin
git -C $bob diff origin/main...origin/docs/add-workflow
git -C $bob log --oneline origin/main..origin/docs/add-workflow
git -C $bob switch main
git -C $bob merge --no-ff origin/docs/add-workflow -m "merge: add review workflow"
git -C $bob push origin main

git -C $alice switch main
git -C $alice pull --ff-only origin main
git -C $alice log --oneline --graph -4
```

Expected result: Bob sees Alice's one-line addition in the diff; after the merge, Alice's `main` fast-forwards to the latest version. In a real GitHub team, Alice opens a pull request and Bob reviews and merges it in the UI rather than pushing directly to a protected `main` branch.

The repository also provides a [PowerShell demo script](../examples/git/team-demo.ps1) that verifies the result and leaves the temporary directory available for inspection.

### 7.3 Further practice: conflicting edits

For further practice, have Alice and Bob edit the same line of `message.txt`. Alice pushes first; Bob's push is rejected. Bob fetches, merges `origin/main` into his branch, resolves the `<<<<<<<`, `=======`, and `>>>>>>>` markers by reading both changes, verifies the result, then commits. Do not blindly choose "ours" or "theirs."

## 8. Incident examples: leaked credential and lost commit

- **Credential already pushed**: revoke or rotate it at the provider first. Add `.env` to `.gitignore` and use `git rm --cached -- .env` to stop tracking it. Deleting it in a new commit does not remove it from older history, forks, or caches. Coordinate any shared-history cleanup with the team.
- **Lost local commit**: find it with `git reflog`, then create `git branch rescue/recovered <commit-id>` and inspect it. Do not reset a shared branch to recover a local commit.

References: [Git branches](https://git-scm.com/docs/git-branch), [Git merge](https://git-scm.com/docs/git-merge), and [Git reflog](https://git-scm.com/docs/git-reflog).
