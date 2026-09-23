# yanruihe.github.io

这是 `yanruihe.github.io` 的 GitHub Pages 静态站点仓库。站点目前由 Hexo 生成，仓库保存的是可直接发布的静态文件。

## 知识库

- [知识库总览](knowledge-base/README.md)
- [Git 知识库](knowledge-base/git.md)
- [Yocto 使用知识库](knowledge-base/yocto.md)
- [线上知识库入口](knowledge-base/)

知识记录统一采用“背景 / 操作 / 验证 / 风险 / 参考资料”的结构。涉及命令、版本或硬件差异时，先在目标环境验证，再提交到仓库。

## 更新站点

```powershell
git switch main
git pull --ff-only origin main
# 修改或重新生成静态页面
git diff --check
git add .
git commit -m "docs: update knowledge base"
git push origin main
```

如果仓库保留 Hexo 源码，推荐在源码仓库生成后再把 `public/` 发布到本仓库；当前仓库没有源 Markdown 和 Hexo 配置，所以本次知识库页面作为静态页面直接维护。
