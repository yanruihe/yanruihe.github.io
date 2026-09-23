# Git 知识库

## 1. Git 如何保存和上传修改

例如你修改了 `README.md`，文件不会自动上传到 GitHub。它会经过下面四步：

1. **工作区**：你在电脑上编辑文件，改动还没有成为 Git 的版本记录。
2. **暂存区**：运行 `git add README.md`，选中这次准备提交的内容。
3. **本地仓库**：运行 `git commit -m "docs: update README"`，在电脑上保存一条提交记录。
4. **远程仓库**：运行 `git push`，把已提交的记录上传到 GitHub。

```bash
git status
git add README.md
git commit -m "docs: update README"
git push
```

`git status` 可以随时查看哪些文件被修改、哪些内容已暂存。`git add` 不是提交，`git commit` 也不会自动上传。如果是新分支首次推送，使用 `git push -u origin HEAD`。

## 2. 推荐日常流程

```bash
git switch main
git pull --ff-only origin main
git switch -c feature/short-description

# 修改后检查变更
git status
git diff
git diff --check

# 只提交相关内容
git add -p
git commit -m "docs: update git notes"

# 提交前同步主线
git fetch origin
git rebase origin/main
git push -u origin HEAD
```

小提交更容易审查和回滚。提交信息建议使用 `docs:`, `feat:`, `fix:`, `build:` 等前缀，并说明结果而不是只描述动作。

## 3. 分支、合并与变基

- 新功能或知识专题使用短生命周期分支，例如 `feature/logging`。
- 本地尚未共享的提交可以用 `rebase` 整理历史。
- 已推送且被别人依赖的提交不要随意重写；需要修正时优先追加修复提交。
- 合并前确认工作区干净，并阅读完整 diff，而不只看最后一个文件。

常用检查：

```bash
git log --oneline --decorate --graph -20
git diff origin/main...HEAD
git diff --name-only origin/main...HEAD
```

## 4. 安全撤销与恢复

```bash
# 取消某个文件尚未提交的工作区修改
git restore -- path/to/file

# 从暂存区移除，但保留工作区修改
git restore --staged -- path/to/file

# 撤销已经发布的提交，生成新的反向提交
git revert <commit>

# 查找丢失的提交或分支指针
git reflog
```

`reset --hard` 会直接丢弃工作区内容，除非已经确认目标和备份，否则不要使用。公共分支的历史修复优先选择 `revert`。

## 5. 提交与评审约定

- 一个提交聚焦一个逻辑变更，方便理解、审查和回滚。
- 提交消息用简短前缀标明类型与范围，例如 `docs(git): clarify restore examples`。
- 提交前检查完整 diff，确认没有密钥、临时文件或无关改动。
- 合并前记录评审意见和验证结果；修正问题时追加清晰的提交。

## 6. 实际案例：只提交需要的改动

场景：`README.md` 和本地配置都改了，但这次只发布文档。先看差异，再明确暂存范围：

```bash
git status -sb
git diff -- README.md
git add README.md
git diff --cached
git diff --cached --check
git commit -m "docs: clarify setup steps"
```

如果暂存错了，用 `git restore --staged -- README.md` 移出暂存区；工作区的编辑仍然保留。需要按代码块选择时可用 `git add -p`。

## 7. 双人协作 Demo：分支、评审、合并与同步

使用 PowerShell，在临时目录中模拟远端、Alice 和 Bob 三个独立仓库；不会改动真实项目。

### 7.1 建立临时远端和两个工作副本

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

### 7.2 Alice 提交功能分支，Bob 评审并合并

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

预期：Bob 的差异检查只看到 Alice 的一行新增内容；合并后 Alice 的 `main` 能快进到最新版本。真实 GitHub 团队一般由 Alice 发起 Pull Request、Bob 在网页上评审并合并，而不是让 Bob 直接推送受保护的 `main`；最后 Alice 同步主线。

也可以下载并运行仓库中的 [PowerShell 演练脚本](examples/git/team-demo.ps1)；脚本会验证最终结果，并保留临时目录供检查。

### 7.3 进阶练习：两人修改同一行造成冲突

再试一个冲突场景：Alice 和 Bob 分别修改 `message.txt` 的同一行；Alice 先推送，Bob 的推送被拒绝。Bob 先 `git fetch origin`，再在自己的分支合并 `origin/main`，手工处理 `<<<<<<<`、`=======`、`>>>>>>>` 标记，运行验证后提交。不要直接选择“保留我的/对方的”来代替阅读实际内容。

## 8. 故障案例：密钥泄露与误删提交

- **密钥已推送**：先在服务端吊销或轮换密钥，再用 `.gitignore` 和 `git rm --cached -- .env` 防止再次提交。删除文件并不能从旧提交、fork 或缓存中清除密钥；共享仓库的历史清理需要团队协调。
- **误删本地提交**：先用 `git reflog` 找到原提交，再建立 `git branch rescue/recovered <commit-id>` 检查内容。不要在共享分支上直接使用 `reset --hard`。

## 9. GitHub SSH 配置与快速使用

以下命令在 Windows PowerShell 中执行。先检查是否已有可用公钥；生成新密钥时，若默认路径已有密钥，不要覆盖它，改用另一个文件名：

```powershell
Get-ChildItem "$HOME/.ssh" -Filter "*.pub" -ErrorAction SilentlyContinue
ssh-keygen -t ed25519 -C "you@example.com"
Get-Content "$HOME/.ssh/id_ed25519.pub"
```

只把 `.pub` 公钥添加到 GitHub 的 **Settings → SSH and GPG keys**；绝不上传私钥。若使用了自定义文件名，相应地修改读取路径，并按需把私钥加入 `ssh-agent`。首次连接前核对 GitHub 官方公布的主机指纹，不能盲目接受提示：

```powershell
ssh -T git@github.com
git remote -v
git remote set-url origin git@github.com:OWNER/REPO.git
git remote -v
```

将 `OWNER/REPO` 换成实际仓库；已有 SSH 远端就不必再次设置。多账号可在 `$HOME/.ssh/config` 中指定别名和密钥：

```sshconfig
Host github-work
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_work
  IdentitiesOnly yes
```

此时远端写成 `git@github-work:TEAM/REPO.git`，测试命令改为 `ssh -T git@github-work`。完成配置后，最短的分支使用流程：

```bash
git clone git@github.com:OWNER/REPO.git
cd REPO
git switch -c feature/quick-note
# 修改 README.md
git add README.md
git commit -m "docs: update README"
git push -u origin HEAD
```

然后发起 Pull Request。这里的 `OWNER/REPO`、`REPO` 和文件名要换成实际值。

## 10. 只修改最后一次 commit 信息

```bash
git status -sb
git show -s --format='%h %s' HEAD
git commit --amend --only -m "docs: clarify setup"
git show -s --format='%h %s' HEAD
```

`--only` 表示只改最后一次提交的说明，不把已暂存的其他文件一起提交；`--amend` 会生成新的 commit ID。只适用于尚未共享、或已与团队约定可以改写的分支。已经发布到共享 `main` 的提交不要为了改文案而强推。

## 11. 多人同时操作同一分支

每人优先使用自己的短期分支并通过 Pull Request 评审；多人共用同一功能分支时，不要对其他人已拉取的提交做 `rebase` 或 `amend`。如果 Bob 已经先推送，而 Alice 的普通 `git push` 被拒绝，Alice 应先检查并整合远端改动：

```bash
git fetch origin
git log --oneline --left-right --graph HEAD...origin/feature/shared
git merge origin/feature/shared
```

无冲突时，运行项目测试后再执行 `git push origin HEAD:feature/shared`。如果 merge 因冲突中断，先编辑文件、删除冲突标记、运行测试，再继续：

```bash
git status
git add path/to/resolved-file
git commit
git push origin HEAD:feature/shared
```

仅在 merge 发生冲突时才需要手工 `git add` / `git commit`；无冲突时 `git merge` 通常会直接完成。合并前检查双方独有提交，合并后运行项目测试。若远端再次前进，重复 fetch、检查和整合，而不是直接强推覆盖 Bob 的提交。

## 12. 覆盖远端分支：仅限已协调的个人分支

覆盖会让远端原有提交脱离分支。先与使用该分支的人确认，并检查远端的准确提交 ID；不要对 `main`、`release/*` 或受保护分支套用此流程。以下 PowerShell 示例只针对 `feature/my-change`：

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

命令只在远端仍指向 `$expected` 时更新该分支；如果有人在检查后又推送，Git 会拒绝。拒绝后重新检查，不能自动重试强推。优先选择新分支加 Pull Request；裸 `--force` 没有上述保护。

## 13. 查看与修改 Git 时间

Git 提交有两个时间：`AuthorDate`（作者写出改动）和 `CommitDate`（提交对象形成）。文件系统的“最后修改时间”是工作区文件属性，不由 Git 提交历史统一保存；`git log` 查的是提交时间。

```bash
git log -1 --format=fuller
git log -1 --date=iso-strict --format='%h %ad %s' -- path/to/file
```

只修改当前分支最后一条**未共享**提交的两个时间，可在 PowerShell 中设置提交者时间，并用 `--date` 设置作者时间。运行前确保日期、时区和目标提交正确：

```powershell
$env:GIT_COMMITTER_DATE = "2026-09-23T10:00:00+08:00"
try {
    git commit --amend --only --no-edit --date="2026-09-23T10:00:00+08:00"
} finally {
    Remove-Item Env:GIT_COMMITTER_DATE -ErrorAction SilentlyContinue
}
git log -1 --format=fuller
```

这会改变 commit ID，但不改文件系统的修改时间。若要**整体改写多条提交的时间**，应先在隔离副本备份并确认分支、标签、签名、CI 和协作者同步方案；可在独立分支用交互式 `git rebase -i --root` 逐条标记 `edit`，每次按上例 amend 日期后 `git rebase --continue`。改动旧提交会连带改写其后所有提交的 ID，含 merge 的历史还需特别处理；不要在共享仓库直接批量执行或强推。

参考：[GitHub SSH 配置](https://docs.github.com/en/authentication/connecting-to-github-with-ssh)、[Git commit 文档](https://git-scm.com/docs/git-commit)、[Git push 与 force-with-lease](https://git-scm.com/docs/git-push)、[Git rebase 文档](https://git-scm.com/docs/git-rebase)。
