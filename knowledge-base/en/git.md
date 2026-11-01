# Git Knowledge Base

Start with identity and SSH setup, then work through cloning, recording changes, reviewing branches, and synchronizing with teammates. Each example includes commands, their purpose, and a result to check.

Git command blocks work in PowerShell or Bash. Scripts labeled PowerShell use PowerShell 7 on Windows. Replace `OWNER/REPO`, email addresses, branch names, and file names with your project values. Read each section's prerequisites before running its commands.

## 1 How Git records changes

### 1.1 Four locations involved in a change

After editing `README.md`, use `git add` to select its content, `git commit` to record a local snapshot, and `git push` to upload commits.

| Location | What it holds | Common operations |
| --- | --- | --- |
| Working tree | Files you are editing | Editor, `git diff` |
| Staging area | Content selected for the next commit | `git add`, `git diff --cached` |
| Local repository | Commits, branches, and tags | `git commit`, `git log` |
| Remote repository | Shared commits and branches | `git fetch`, `git push` |

```text
Edit files → git add → staging area → git commit → local commit → git push → remote branch
```

Edits made after staging remain in the working tree until staged again. A local commit reaches the remote only after a push.

### 1.2 Inspect status and differences

From the project directory, run:

```bash
git status -sb
git diff
git diff --cached
```

`git diff` shows unstaged changes. `git diff --cached` compares staged content with the current commit. In the short status output, the first file-status column describes the index and the second describes the working tree.

| Status example | Meaning |
| --- | --- |
| ` M README.md` | Modified in the working tree, not staged |
| `M  README.md` | Modification is staged |
| `MM README.md` | Staged, then edited again |
| `?? notes.txt` | Untracked file |

## 2 Git environment and GitHub SSH setup

### 2.1 Check Git and your commit identity

```bash
git --version
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
git config --get user.name
git config --get user.email
```

The name and email become part of your commits. To use a different identity for one repository, configure it inside that repository without `--global`. Confirm that the displayed identity matches the project.

### 2.2 Generate a key and add the public key

First inspect existing public keys in PowerShell:

```powershell
$sshDir = Join-Path $env:USERPROFILE ".ssh"
Get-ChildItem $sshDir -Filter "*.pub" -ErrorAction SilentlyContinue
```

Reuse an appropriate existing key, or create a new key with its own filename:

```powershell
New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
$keyFile = Join-Path $sshDir "id_ed25519_github"
if (Test-Path $keyFile) { throw "Key already exists; reuse it or choose another filename." }
ssh-keygen -t ed25519 -C "you@example.com" -f $keyFile
Get-Content "$keyFile.pub"
```

Choose a passphrase when prompted. Add the public-key output under GitHub **Settings → SSH and GPG keys → New SSH key**. Keep the file without the `.pub` suffix private.

### 2.3 Test authentication and configure the remote

Before accepting a new host, compare its fingerprint with [GitHub's published fingerprints](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints). Test the custom key:

```powershell
ssh -T -i $keyFile -o IdentitiesOnly=yes git@github.com
```

A successful response identifies the authenticated account and says that shell access is unavailable. The test can exit with status `1` even after successful authentication; read the response.

To select this key for later Git connections, add the following to `$sshDir/config`:

```sshconfig
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_github
  IdentitiesOnly yes
```

Inside an existing repository, inspect and update the remote:

```bash
git remote -v
git remote set-url origin git@github.com:OWNER/REPO.git
git remote -v
```

Expected result: both fetch and push URLs for `origin` point to the intended repository. Changing a URL does not upload files.

### 2.4 Use separate keys for multiple accounts

Add an alias for a work account to SSH config:

```sshconfig
Host github-work
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_work
  IdentitiesOnly yes
```

Use `git@github-work:TEAM/REPO.git` for that account's remote, and test with `ssh -T git@github-work`. The alias selects the SSH identity; `user.name` and `user.email` still control commit identity.

## 3 From cloning to the first push

### 3.1 Clone and create a working branch

```bash
git clone git@github.com:OWNER/REPO.git
cd REPO
git switch main
git pull --ff-only origin main
git switch -c feature/quick-note
```

`clone` creates a local copy. `pull --ff-only` accepts only a fast-forward update. `switch -c` creates a branch from the current commit and switches to it. Replace `main` if the project uses another main-branch name.

Check the branch:

```bash
git branch --show-current
git status -sb
```

Expected result: `feature/quick-note`. If the fast-forward pull is rejected, inspect the divergence and choose a merge or rebase as described in section 4.

### 3.2 Edit a file and record a commit

Edit and save `README.md` in your editor, then run:

```bash
git diff -- README.md
git add README.md
git diff --cached
git diff --cached --check
git commit -m "docs: update README"
```

Review the diff before staging the intended file. `--check` checks the diff for whitespace errors and conflict markers. The staged diff shows the content that the commit will record.

Verify the result:

```bash
git log -1 --oneline
git status -sb
```

The new commit should appear in the log, and its recorded changes should disappear from the status list.

### 3.3 Push the branch and request review

```bash
git push -u origin HEAD
git branch -vv
```

`HEAD` refers to the current branch; `-u` sets its upstream. Confirm that `git branch -vv` shows `origin/feature/quick-note`, then open a pull request describing the purpose and verification results.

## 4 Branch merging and rebasing

### 4.1 Inspect branches and commit relationships

```bash
git fetch origin
git branch -a
git log --oneline --decorate --graph -20
git diff origin/main...HEAD
```

`fetch` updates remote-tracking information without merging it into your current branch. The three-dot diff starts at the common ancestor and is useful for reviewing changes introduced by your branch.

### 4.2 Choose merge or rebase

| Operation | Effect on history | Typical use |
| --- | --- | --- |
| `merge` | Preserves existing commits and may add a merge commit | Integrating a branch already shared with others |
| `rebase` | Replays commits on a new base, usually producing new IDs | Tidying your own unpublished commits |

Merge the latest main branch into the current feature branch:

```bash
git fetch origin
git merge origin/main
```

For a branch containing only your own unpublished commits, another option is:

```bash
git fetch origin
git rebase origin/main
```

Afterward, review the commit graph and complete diff, then run the project's checks. Coordinate history changes if teammates have already built on those commits.

### 4.3 Continue or abort an interrupted operation

| Operation | After resolving conflicts | To abandon the operation |
| --- | --- | --- |
| merge | `git add`, then `git commit` | `git merge --abort` |
| rebase | `git add`, then `git rebase --continue` | `git rebase --abort` |

Save and handle existing edits before starting a merge or rebase. The abort commands exit an operation currently in progress.

## 5 Selective commits and review

### 5.1 Commit only the documentation

Scenario: `README.md` and a local configuration file have changed, but this commit should include only the documentation.

```bash
git status -sb
git diff -- README.md
git add README.md
git diff --cached
git diff --cached --check
git commit -m "docs: clarify setup steps"
```

Expected result: the commit contains the README change, while the local configuration edit remains in the working tree.

### 5.2 Stage hunks and unstage a file

```bash
git add -p
git diff --cached
git restore --staged -- README.md
```

`add -p` lets you select individual hunks. `restore --staged` removes the file from the staging area while preserving working-tree edits; you can then stage the intended parts again.

### 5.3 Commit and review conventions

Keep each commit focused on one logical change, with a clear message such as `docs(git): clarify restore examples`. Review the complete diff for temporary files, account information, and unrelated changes. Record checks and review conclusions before merging. Small commits make problems easier to locate and revert.

## 6 Two-person collaboration demo

This PowerShell example creates a temporary bare remote and independent clones for Alice and Bob. `git -C` chooses the repository in which each command runs, so both roles can be demonstrated in one terminal.

### 6.1 Create the remote and two clones

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

`--bare` creates a repository for sharing commits without an editable working tree. Cloning the empty repository produces a notice. Bob clones only after Alice has pushed the initial `main` commit.

### 6.2 Alice pushes a feature branch

```powershell
git -C $alice switch -c docs/add-workflow
Add-Content (Join-Path $alice "README.md") "Review changes before merging."
git -C $alice add README.md
git -C $alice commit -m "docs: add review workflow"
git -C $alice push -u origin docs/add-workflow
```

Expected result: the remote has a new `docs/add-workflow` branch, while `main` remains unchanged.

### 6.3 Bob merges and Alice synchronizes

```powershell
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

Bob should see Alice's one-line addition. `--no-ff` records an explicit merge commit. Alice can then fast-forward to the new `main`, and both README files should match.

The local demo uses direct pushes to illustrate branch relationships. Real teams normally use pull requests and reviews, with protected main branches updated according to project policy.

The [complete PowerShell demo script](/knowledge-base/examples/git/team-demo.ps1) checks the final commits and file contents, and leaves the temporary directory available for inspection.

## 7 Shared branches and conflict resolution

### 7.1 Inspect both sides after a rejected push

Scenario: Bob has pushed to `feature/shared` before Alice, so Alice's ordinary push is rejected as non-fast-forward. From that branch, Alice runs:

```bash
git fetch origin
git log --oneline --left-right --graph HEAD...origin/feature/shared
git merge origin/feature/shared
```

The left/right markers identify commits unique to the local and remote sides. A conflict-free merge normally completes automatically; after verification, run `git push origin HEAD:feature/shared`.

### 7.2 Resolve edits to the same line

If both people edited the same line in `message.txt`, the merge may pause. Use `git status` to find the conflicted file and inspect it in your editor:

```text
  <<<<<<< HEAD
  message from Alice
  =======
  message from Bob
  >>>>>>> origin/feature/shared
```

Edit the intended final content, remove the conflict markers, save, and continue:

```bash
git diff --check
git add message.txt
git commit
git push origin HEAD:feature/shared
```

Expected result: no unmerged files in `git status` and the project's checks pass. If the remote advances again, fetch and integrate again. To abandon the current merge, use `git merge --abort`.

## 8 Change commit messages

### 8.1 Change only the last commit message

Inspect the target commit, then run:

```bash
git status -sb
git show -s --format='%h %s' HEAD
git commit --amend --only -m "docs: clarify setup"
git show -s --format='%h %s' HEAD
git diff 'HEAD@{1}' HEAD --
git diff --cached
```

With no file paths, `--amend --only` replaces the last commit message without adding unrelated staged changes. The diff between the old and new file trees should be empty, while existing staged changes remain visible in `git diff --cached`.

The commit ID changes. Use this for your own unpublished commit or a branch whose rewrite has been agreed with collaborators.

### 8.2 Edit earlier commit messages

If the three commits to edit have an earlier parent and may be rewritten, run:

```bash
git rebase -i HEAD~3
```

Change `pick` to `reword` for the intended commits, save, and edit the messages when prompted. Check `git log --oneline -3` afterward. Use `git rebase --abort` to leave an unfinished rebase.

## 9 Replace a remote branch

### 9.1 Record the remote commit to be replaced

This example targets a personal `feature/my-change` branch whose rewrite has been coordinated. Inspect the working tree and current branch, then capture the fetched remote commit:

```powershell
git status -sb
if ((git branch --show-current) -ne "feature/my-change") { throw "Switch to feature/my-change first" }
git fetch origin
$expected = git rev-parse --verify refs/remotes/origin/feature/my-change
if ($LASTEXITCODE -ne 0) { throw "Remote-tracking branch not found" }
git log --oneline --left-right --graph "HEAD...$expected"
git branch ("backup/my-change-" + (Get-Date -Format yyyyMMddHHmmss)) $expected
```

`$expected` remains fixed at the fetched commit you are about to review. Inspect both sides before deciding to replace the branch. The backup branch preserves this remote version for comparison or recovery.

### 9.2 Push with an explicit expected commit

After reviewing the replacement, run:

```powershell
git push "--force-with-lease=refs/heads/feature/my-change:$expected" origin HEAD:refs/heads/feature/my-change
git ls-remote origin refs/heads/feature/my-change
git rev-parse HEAD
```

The push updates the remote only if it still points to `$expected`. After a successful push, the last two commands should report the same commit ID. If someone has pushed in the meantime, the lease rejects the replacement; fetch and review again.

> Replacing a branch changes the history it points to. This example is for a coordinated personal feature branch. For a branch others depend on, agree on their synchronization procedure first.

## 10 Inspect and change Git dates

### 10.1 How the three timestamps differ

| Timestamp | Meaning | How to inspect it |
| --- | --- | --- |
| AuthorDate | Author timestamp recorded in a commit | `git log --format=fuller` |
| CommitDate | Committer timestamp recorded in a commit | `git log --format=fuller` |
| File modification time | A working-tree filesystem attribute | Operating-system file properties |

```bash
git log -1 --format=fuller
git log -1 --date=iso-strict --format='%h %ad %cd %s' -- path/to/file
```

`%ad` shows the author date and `%cd` the committer date. Git does not store filesystem mtime as versioned file content; changing commit dates does not set all working-tree file times.

### 10.2 Change the last unpublished commit dates

The PowerShell example below sets both dates. Replace the example timestamp with the intended value:

```powershell
$previousCommitterDate = $env:GIT_COMMITTER_DATE
try {
    $env:GIT_COMMITTER_DATE = "2026-09-23T10:00:00+08:00"
    git commit --amend --only --no-edit --date="2026-09-23T10:00:00+08:00"
} finally {
    $env:GIT_COMMITTER_DATE = $previousCommitterDate
}
git log -1 --format=fuller
```

`--date` sets the author date, the environment variable sets the committer date, and `--no-edit` preserves the message. Inspect both dates, their time zones, and the file diff afterward. The commit ID changes.

### 10.3 Adjust dates across several commits

In an isolated copy, preserve the original branch and decide how to handle tags, signatures, merge commits, and collaborators. Use `git rebase -i --root` and mark the intended commits `edit`. At each stop, amend the dates as above, then run `git rebase --continue`.

Changing an older commit changes descendant IDs too. For histories containing merges, establish how merge relationships will be retained. Review the complete commit graph and file trees, and run project checks before sharing the result.

## 11 Undo changes and recover versions

### 11.1 Choose a command for the location of the change

| Intended action | Command | Result |
| --- | --- | --- |
| Unstage a file | `git restore --staged -- file` | Working-tree edits remain |
| Discard unstaged edits | `git restore -- file` | Restores from the index, overwriting the corresponding working-tree edits |
| Undo a published commit | `git revert COMMIT` | Creates an inverse commit |

For example, unstage the README:

```bash
git restore --staged -- README.md
git status -sb
git diff -- README.md
```

Expected result: the edit remains but is no longer staged. Before using `restore` to overwrite a working-tree file, confirm which edits you intend to discard.

### 11.2 Revert a published commit

```bash
git log --oneline -5
git revert COMMIT_ID
git show --stat HEAD
```

Replace `COMMIT_ID` with the ordinary commit to undo. Inspect the inverse commit, run checks, and push normally. Reverting a merge also requires choosing the mainline parent.

`reset --hard` resets the index and overwrites the corresponding working-tree content. An inverse commit keeps a shared-branch correction visible for review.

## 12 Common problems and incident examples

### 12.1 Recover a lost local commit

```bash
git reflog
git branch rescue/recovered COMMIT_ID
git show --stat rescue/recovered
```

Find the intended commit in the reflog, create a rescue branch, and inspect it. Reflogs are local and have retention limits; preserve a needed commit on a regular branch after checking it.

### 12.2 Handle a committed credential

First revoke or rotate the credential at its provider. Add `.env` to `.gitignore`, then stop tracking the file:

```bash
git rm --cached -- .env
git add .gitignore
git commit -m "chore: stop tracking local environment"
```

`--cached` retains the local file. A deletion commit does not remove a credential from old history, forks, or caches; coordinate history cleanup with the repository maintainers and collaborators.

## 13 References

- [GitHub SSH setup and testing](https://docs.github.com/en/authentication/connecting-to-github-with-ssh)
- [Git commit and amend](https://git-scm.com/docs/git-commit)
- [Git merge](https://git-scm.com/docs/git-merge) and [Git rebase](https://git-scm.com/docs/git-rebase)
- [Git push and force-with-lease](https://git-scm.com/docs/git-push)
- [Git restore](https://git-scm.com/docs/git-restore) and [Git reflog](https://git-scm.com/docs/git-reflog)

[Back to Knowledge Base](/knowledge-base/en/)
