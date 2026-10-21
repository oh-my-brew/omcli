# omcli 工程约定

本文件适用于整个仓库。`README.md` 面向用户，`RELEASING.md` 记录产品发行流程；这里保存开发、验证和委派边界。

## 开发

- 开始前检查 Git 状态，保留用户与其他会话的修改；不要 reset、clean、stash、强推或擅自切换分支。
- 源码修改应补充隔离的自动化测试并同步用户文档。可以运行 `make build`、`sh tests/test.sh`、Shell 语法检查和其他不会改变真实系统状态的检查。
- 不在本地测试真实功能，不把开发产物安装到 Homebrew prefix。不得执行锁屏、磁盘扫描或清理、Sidecar 连接、iPhone SSH、Codex writer 恢复等有副作用的命令。
- 自动化检查通过不等于功能已经人工验证；交付时明确列出未做的运行时验证。

## 开发完成后的候选发行

- 用户已决定：正常开发任务的代码进入 `main` 且源码 CI 通过后，自动创建一个新的 Beta Release subagent；用户明确说“只开发”或“不要发布”时除外。
- 不使用固定历史会话。Beta Release subagent 只接收产品名、准确源码 commit、变更摘要、自动化检查和未验证项，不继承不必要的完整聊天上下文。
- Beta Release subagent 使用独立 Git worktree，固定源码 commit，先确认没有同产品候选发行正在进行，再按 `RELEASING.md` 创建版本候选、版本 PR 并发布不可变 beta。主会话启动后不轮询、不等待，保持可继续响应其他任务。
- 如果无法创建 subagent、发行状态冲突或需要用户处理权限，停止自动链路并报告；不要悄悄退回开发主会话执行长时间发行。

## 正式提升

- beta 不自动成为正式版。只有用户明确指出批准的 beta tag 及对应 SHA-256 后，主会话才新建独立 Promote subagent；主会话同样不等待其执行。
- Promote subagent 必须从 GitHub API 读取默认分支、拉取准确的远端 HEAD，并验证版本 PR 已合入、候选 commit 是该 HEAD 的祖先、候选仍为 prerelease、实际 SHA-256 同时匹配候选校验文件和用户批准值、归档结构有效，然后复用用户批准的同一份 tar.gz 和校验文件创建稳定 Release。
- 不重新打包，不允许用另一个候选替代用户批准的 tag；失败后停止，不自动改发新版本。
- 候选合入优先使用保留原 SHA 的普通非强推 fast-forward；依 `RELEASING.md` 复核远端、批准及 CI 后执行并回读。不得为发行关闭或绕过分支保护；分叉、并发变化或保护拒绝时停止，不 squash/rebase 已批准候选。

## Homebrew 解耦

- 产品 GitHub Release 完整验证后，本次发行结束。Beta/Promote subagent 不读取或修改 Homebrew Tap，不触发 Autobump，也不安装三台设备。
- Homebrew Tap 通过每日定时 Autobump 独立追踪稳定 Release；其检查、合并和安装按 Tap 仓库规则另行处理。

## 权限与失败边界

- 上述自动产品发行是用户确认的默认工作流；版本冲突、签名/凭据失败、需要改变发行范围或工作流安全检查失败时再请求用户处理。
- 暂不发送飞书通知；以 subagent 完成或失败回报为准。
- 不为通过发行而降低检查、重跑有副作用命令、覆盖已有 tag/Release、强推、删除远端历史或修改无关包。
