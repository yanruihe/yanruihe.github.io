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

## 9. GitHub SSH setup and quick start

Run these commands in Windows PowerShell. Check for an existing public key first. If the default key path is already in use, choose another filename instead of overwriting it:

```powershell
Get-ChildItem "$HOME/.ssh" -Filter "*.pub" -ErrorAction SilentlyContinue
ssh-keygen -t ed25519 -C "you@example.com"
Get-Content "$HOME/.ssh/id_ed25519.pub"
```

Add only the `.pub` public key to GitHub **Settings → SSH and GPG keys**; never upload the private key. Adjust the path if you chose a custom filename, and add the private key to `ssh-agent` if needed. On the first connection, compare the host fingerprint with GitHub's published fingerprint before accepting it:

```powershell
ssh -T git@github.com
git remote -v
git remote set-url origin git@github.com:OWNER/REPO.git
git remote -v
```

Replace `OWNER/REPO` with the actual repository. An existing SSH remote does not need to be changed. For multiple accounts, an alias in `$HOME/.ssh/config` can select a specific key:

```sshconfig
Host github-work
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_work
  IdentitiesOnly yes
```

Then use `git@github-work:TEAM/REPO.git` as the remote and test with `ssh -T git@github-work`. The short workflow is:

```bash
git clone git@github.com:OWNER/REPO.git
cd REPO
git switch -c feature/quick-note
# Edit README.md
git add README.md
git commit -m "docs: update README"
git push -u origin HEAD
```

Then open a pull request. Replace `OWNER/REPO`, `REPO`, and the file name with real values.

## 10. Change only the last commit message

```bash
git status -sb
git show -s --format='%h %s' HEAD
git commit --amend --only -m "docs: clarify setup"
git show -s --format='%h %s' HEAD
```

`--only` changes the message without including unrelated staged changes; `--amend` creates a new commit ID. Use it only on an unpublished commit or a branch whose history rewrite was agreed with the team. Do not force-push shared `main` just to fix wording.

## 11. Several people on the same branch

Prefer short-lived personal branches and pull requests. On a shared feature branch, do not rebase or amend commits that teammates may have pulled. If Bob pushed first and Alice's ordinary push is rejected, Alice should inspect and integrate the remote changes:

```bash
git fetch origin
git log --oneline --left-right --graph HEAD...origin/feature/shared
git merge origin/feature/shared
```

If the merge succeeds, run project tests before `git push origin HEAD:feature/shared`. If it stops on conflicts, edit the files, remove conflict markers, run tests, then continue:

```bash
git status
git add path/to/resolved-file
git commit
git push origin HEAD:feature/shared
```

Run `git add` / `git commit` manually only if the merge stops on conflicts; otherwise Git normally completes the merge itself. Review each side's unique commits and run project tests. If the remote advances again, fetch and integrate again rather than overwriting Bob's commit.

## 12. Replace a remote branch: only a coordinated personal branch

A forced update can detach the remote's previous commits from its branch. Coordinate with anyone using that branch and check its exact remote commit ID first. Never apply this example to `main`, `release/*`, or a protected branch. This PowerShell example targets only `feature/my-change`:

```powershell
git status -sb
if ((git branch --show-current) -ne "feature/my-change") { throw "Switch to feature/my-change first" }
git fetch origin
git log --oneline --left-right --graph HEAD...origin/feature/my-change
git branch backup/feature-my-change origin/feature/my-change
$remoteLine = git ls-remote origin refs/heads/feature/my-change
$expected = ($remoteLine -split "\s+")[0]
if (-not $expected) { throw "Remote branch not found" }
git push "--force-with-lease=refs/heads/feature/my-change:$expected" origin HEAD:refs/heads/feature/my-change
```

The push succeeds only if the remote still points at `$expected`. If someone pushes after your check, Git rejects it. Reinspect the branch; do not automatically retry a force push. A new branch and pull request are preferable, while bare `--force` lacks this protection.

## 13. Inspect and change Git timestamps

Commits have an `AuthorDate` (when the author wrote the change) and a `CommitDate` (when the commit object was created). A working-tree file's filesystem modification time is not preserved as one repository-wide Git timestamp. `git log` reports commit history, not the file's current filesystem mtime.

```bash
git log -1 --format=fuller
git log -1 --date=iso-strict --format='%h %ad %s' -- path/to/file
```

To change both dates of the last **unshared** commit in PowerShell, set the committer date in the environment and the author date with `--date`. Confirm the timestamp, time zone, and target commit first:

```powershell
$env:GIT_COMMITTER_DATE = "2026-09-23T10:00:00+08:00"
try {
    git commit --amend --only --no-edit --date="2026-09-23T10:00:00+08:00"
} finally {
    Remove-Item Env:GIT_COMMITTER_DATE -ErrorAction SilentlyContinue
}
git log -1 --format=fuller
```

This changes the commit ID, not filesystem modification times. To **rewrite timestamps across multiple commits**, first work in an isolated backup and plan how branches, tags, signatures, CI, and collaborators will be handled. On an isolated branch, `git rebase -i --root` lets you mark commits `edit`; amend each date as above, then run `git rebase --continue`. Editing an older commit changes the IDs of all its descendants. Merge-heavy histories need extra care; do not run a blanket rewrite or force-push directly in a shared repository.

References: [GitHub SSH setup](https://docs.github.com/en/authentication/connecting-to-github-with-ssh), [Git commit](https://git-scm.com/docs/git-commit), [Git push and force-with-lease](https://git-scm.com/docs/git-push), and [Git rebase](https://git-scm.com/docs/git-rebase).
