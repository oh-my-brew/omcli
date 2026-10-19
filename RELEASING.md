# omcli 候选与正式发行

## 前提

- 开发提交已经进入 `main`，源码 CI 通过，仓库和远端状态清楚。
- 没有正在进行的 omcli 版本 PR、beta 或正式 Release。
- 发行在独立 worktree 中执行，不占用开发主会话的工作树。
- 不运行任何真实 omcli 功能作为发行验证。

## Beta Release subagent

1. 以 Asia/Shanghai 的当前日期和已有 Release 确定 `YYYY.MM.DD.N`，同日递增 `N`，不得复用或覆盖现有版本。
2. 在独立 worktree 中从用户批准的准确开发 commit 创建版本分支，只修改 `VERSION` 及确有需要的发行说明；记录候选 commit SHA。
3. 创建版本 PR，但不自动合并。确定下一个 beta 序号并以候选 commit 调用 Beta workflow。
4. 共享 `source-beta.yml` checkout 该 40 位 SHA，执行 `make build && sh tests/test.sh`，两次生成完全一致的 `omcli-VERSION.tar.gz` 后创建 `vVERSION-beta.N` prerelease。
5. 核对 prerelease tag、目标 commit、归档、SHA 和 `omcli update --beta` 入口。完成或失败后回报，subagent 结束；主会话不等待它。

用户可运行 `omcli update --beta` 安装最新候选。正式 `omcli update`、GitHub
latest 和 Homebrew 仍只读取稳定 Release。

## Promote subagent

用户明确批准具体 beta tag 及其 SHA-256 后才开始：

1. 使用新的独立 worktree，锁定用户批准的 beta tag 和 SHA-256，不以“最新 beta”或重新读取出的摘要替代用户批准值。
2. 使用保留候选 commit 的 merge commit 方式合入版本 PR；不 squash 或 rebase。
3. 运行 Promote workflow。它从 GitHub API 获取默认分支、显式 fetch 准确的远端 HEAD，确认候选 commit 是该 HEAD 的祖先、候选仍为 prerelease，且不存在同版本稳定 Release。
4. 下载候选 tar.gz 和 SHA，验证实际摘要同时匹配候选校验文件与用户批准值，并验证路径、链接、内嵌 `VERSION` 与候选 commit。
5. 将同一份资产附加到 `vVERSION` 正式 Release；不重新构建或打包。
6. 核对正式 tag、Release、资产 SHA 仍与候选及批准值一致，并确认 `omcli update` 可发现稳定版本。到此产品发行完成。

任何失败都不得自动提升。版本冲突、候选 commit 未进入 `main`、摘要不一致或资产结构异常时停止并报告。

`v2026.10.19.1-beta.1` 的 tag 错误指向
`8a957c3409675b2e9484e9003236ac85e50b66b8`，而打包的候选 commit 是
`85a82223426e0d3c14d76bea3d06b3a5d6c5348a`。该候选保留作为审计记录，Promote
workflow 会明确拒绝它；不得删除、移动或提升此 tag。

## Homebrew 解耦

产品 Release 不触发或等待 Homebrew Tap。Tap 每日定时发现新版本并创建升级 PR；Bottle、PR 合并和 Homebrew 升级由独立维护流程处理。

## 首次启用顺序

包含 `source-beta.yml` 与 `promote-source-beta.yml` 的 brew-ci 改动已经合入默认分支；
omcli 两个 workflow 固定到该合入 commit 的完整 40 位 SHA
`6e26fbaf6abe40fa277497a0b68d44c90ee02297`。后续升级共享流程时必须同时更新两处，
不能改用 `main` 或 tag 等移动引用。

最终交付应包含源码 commit、版本 PR、beta tag、正式 tag、两个 Release、相同资产 SHA、隔离测试，以及未做的功能测试。
