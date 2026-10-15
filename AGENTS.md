# omcli 工程约定

本文件适用于整个仓库。`README.md` 面向用户，`RELEASING.md` 记录产品发行流程；这里保存开发、验证和委派边界。

## 开发

- 开始前检查 Git 状态，保留用户与其他会话的修改；不要 reset、clean、stash、强推或擅自切换分支。
- 源码修改应补充隔离的自动化测试并同步用户文档。可以运行 `make build`、`sh tests/test.sh`、Shell 语法检查和其他不会改变真实系统状态的检查。
- 不在本地测试真实功能，不把开发产物安装到 Homebrew prefix。不得执行锁屏、磁盘扫描或清理、Sidecar 连接、iPhone SSH、Codex writer 恢复等有副作用的命令。
- 自动化检查通过不等于功能已经人工验证；交付时明确列出未做的运行时验证。

## 开发完成后的发行

- 用户已决定：正常开发任务的代码进入 `main` 且源码 CI 通过后，自动创建一个新的 Release subagent；用户明确说“只开发”或“不要发布”时除外。
- 不使用固定历史会话。Release subagent 只接收产品名、准确源码 commit、变更摘要、自动化检查和未验证项，不继承不必要的完整聊天上下文。
- Release subagent 使用独立 Git worktree，先确认没有同产品发行正在进行，再按 `RELEASING.md` 完成版本 PR、合并、产品 Release、Homebrew Tap 和三机安装。主会话保持可继续响应其他任务。
- 如果无法创建 subagent、发行状态冲突或需要用户处理权限，停止自动链路并报告；不要悄悄退回开发主会话执行长时间发行。

## Homebrew 阶段

- 产品 GitHub Release 完整验证后，Release subagent 获取远程 `oh-my-brew/homebrew-tap` 默认分支的准确 commit，并从同一 commit 读取 `AGENTS.md` 与 `RELEASES.md`。
- 不使用本地同级 `homebrew-tap` checkout 作为正式规则来源，不在正常产品发行中修改其本地工作树。Tap 操作以远程文件、workflow、PR 和 Actions 的实时状态为准。
- Homebrew 阶段仍由同一个 Release subagent 继续，不再串行创建额外 Tap subagent。

## 权限与失败边界

- 上述自动发行与三机定向安装是用户确认的默认工作流；版本冲突、签名/凭据失败、需要改变发行范围或工作流安全检查失败时再请求用户处理。
- 不为通过发行而降低检查、重跑有副作用命令、覆盖已有 tag/Release、强推、删除远端历史或修改无关包。
