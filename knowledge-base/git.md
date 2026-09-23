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

## 6. 发布到远程仓库

```bash
git fetch origin
git switch main
git pull --ff-only origin main
git switch -c docs/update-git-notes
# 修改 Git 文档或相关文件
git diff --check
git add path/to/changed-files
git commit -m "docs(git): update workflow notes"
git push -u origin HEAD
```

参考：[Git 分支文档](https://git-scm.com/docs/git-branch)、[Git 变基文档](https://git-scm.com/docs/git-rebase)、[Git 拉取文档](https://git-scm.com/docs/git-pull)。
