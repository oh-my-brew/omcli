# omcli 发行

## 前提

- 开发提交已经进入 `main`，源码 CI 通过，仓库和远端状态清楚。
- 没有正在进行的 omcli 版本 PR 或 Release。
- 发行在独立 worktree 中执行，不占用开发主会话的工作树。
- 不运行任何真实 omcli 功能作为发行验证。

## 产品版本

1. 以 Asia/Shanghai 的当前日期和已有 Release 确定 `YYYY.MM.DD.N`，同日递增 `N`，不得复用或覆盖现有版本。
2. 从最新 `main` 创建独立版本分支，只修改 `VERSION` 及确有需要的发行说明。
3. 创建版本 PR，等待最新 head 的源码测试和必需检查通过后合并。
4. `VERSION` 进入 `main` 后触发 `.github/workflows/release.yml`。共享 `source-release.yml` 执行 `make build && sh tests/test.sh`，创建 `vVERSION`、GitHub Release、`omcli-VERSION.tar.gz` 和摘要。
5. 核对 tag 指向预期 commit、Release 完成、源码包及 SHA 完整，并确认包中包含全部 `bin/*`。到此产品发行完成。

手动运行 Release workflow 默认 `publish=false`，只能用于验证和打包；除非本次任务明确要求恢复失败的自动发行，不用 `publish=true` 绕过版本 PR。

## Homebrew 解耦

产品 Release 不触发或等待 Homebrew Tap。Tap 每日定时发现新版本并创建升级 PR；Bottle、PR 合并和 Homebrew 升级由独立维护流程处理。

最终交付应包含源码 commit、版本 PR、tag、Release、资产 SHA、隔离测试，以及未做的功能测试。
