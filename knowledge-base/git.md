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

下面根据本地 `git/demo/02-功能分支开发并合并.md` 和 `git/demo/03-多人同时修改导致冲突.md` 改写。使用 PowerShell，在临时目录中模拟远端、Alice 和 Bob 三个独立仓库；不会改动真实项目。

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

本地 `git/demo/03-多人同时修改导致冲突.md` 还演示了：Alice 和 Bob 分别修改 `message.txt` 的同一行；Alice 先推送，Bob 的推送被拒绝。Bob 先 `git fetch origin`，再在自己的分支合并 `origin/main`，手工处理 `<<<<<<<`、`=======`、`>>>>>>>` 标记，运行验证后提交。不要直接选择“保留我的/对方的”来代替阅读实际内容。

## 8. 故障案例：密钥泄露与误删提交

- **密钥已推送**：先在服务端吊销或轮换密钥，再用 `.gitignore` 和 `git rm --cached -- .env` 防止再次提交。删除文件并不能从旧提交、fork 或缓存中清除密钥；共享仓库的历史清理需要团队协调。
- **误删本地提交**：先用 `git reflog` 找到原提交，再建立 `git branch rescue/recovered <commit-id>` 检查内容。不要在共享分支上直接使用 `reset --hard`。

以上案例来自本地 `F:\MyBrain\git` 知识库。参考：[Git 分支文档](https://git-scm.com/docs/git-branch)、[Git 合并文档](https://git-scm.com/docs/git-merge)、[Git reflog 文档](https://git-scm.com/docs/git-reflog)。
