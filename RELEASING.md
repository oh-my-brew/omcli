# omcli 发行

## 前提

- 开发提交已经进入 `main`，源码 CI 通过，仓库和远端状态清楚。
- 没有正在进行的 omcli 版本 PR、Release 或 Tap 更新。
- 发行在独立 worktree 中执行，不占用开发主会话的工作树。
- 不运行任何真实 omcli 功能作为发行验证。

## 产品版本

1. 以 Asia/Shanghai 的当前日期和已有 Release 确定 `YYYY.MM.DD.N`，同日递增 `N`，不得复用或覆盖现有版本。
2. 从最新 `main` 创建独立版本分支，只修改 `VERSION` 及确有需要的发行说明。
3. 创建版本 PR，等待最新 head 的源码测试和必需检查通过后合并。
4. `VERSION` 进入 `main` 后触发 `.github/workflows/release.yml`。共享 `source-release.yml` 执行 `make build && sh tests/test.sh`，创建 `vVERSION`、GitHub Release、`omcli-VERSION.tar.gz` 和摘要。
5. 核对 tag 指向预期 commit、Release 完成、源码包及 SHA 完整，并确认包中包含全部 `bin/*`。产品 Release 未完成时不得进入 Tap 阶段。

手动运行 Release workflow 默认 `publish=false`，只能用于验证和打包；除非本次任务明确要求恢复失败的自动发行，不用 `publish=true` 绕过版本 PR。

## Homebrew 与三机安装

产品 Release 成功后，按 `AGENTS.md` 固定远程 `oh-my-brew/homebrew-tap` 的规则 commit，读取其中的 `AGENTS.md` 与 `RELEASES.md`，执行 omcli 对应的 Autobump、Bottle、Tap PR 和三机安装流程。

最终交付应包含源码 commit、版本 PR、tag、Release、资产 SHA、Tap PR 与 merge commit、M1/M2/M5 安装版本、Bottle 验证，以及未做的功能测试。
