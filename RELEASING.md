# omcli 候选与正式发行

## 发布代理的复用、交接与收尾

- 每个产品同时只保留一个未交接的发布代理；委派前核对已有代理回执及 GitHub 上实际运行的 Beta/Promote。跨开发会话不能各自再开一个代理。该门禁是执行约定，不是全局调度器；不能以 GitHub concurrency 代替本机代理数量检查。
- 活跃或可恢复的原代理承接同一产品的重试和正式提升，不为 Beta、Promote、网络重试分别新建代理。新源码仍走现有候选冲突/取代检查，不能向正在写入的代理塞入另一个发行目标。代理不得嵌套派生。
- 临时网络错误先回读远端，确认操作是否已成功，再有界重试（同一操作最多三次）。摘要、签名、批准或安全检查失败不盲目重试。完成、失败、阻塞及待用户体验都是必须交接的结果；等待人工体验或权限时不让代理长期驻留。
- 派发 CI 后立即向主会话发一次受理消息，包含精确 run URL 和目标 commit。由发布代理低频观察同一 CI；主会话不重复 watch、不另开进度查询代理。阶段结束再发送结果，不逐条转发日志。

### 持久回执

在仓库共享 Git 目录（`git rev-parse --path-format=absolute --git-common-dir`）下保存
`release-agent/<operation-id>.json`；所有 worktree 读取同一位置。它是本机恢复材料，
不提交 Git、不放源码树、不写凭据。另在已有版本 PR 记录非敏感候选身份与结果；尚无 PR
时以本机回执交接，不能为报告结果额外创建版本 PR。

回执至少包含：产品、operation ID、主会话与代理标识、准确源码及候选 commit、版本、
当前阶段（beta/promote）、结果（running/beta_ready/released/failed/blocked/cancelled）、
PR/run/Release URL、资产 SHA-256、检查及未验证项、阻塞和下一步、更新时间，
以及 `acknowledged_at`、`reported_to_user_at`、`close_status`。
未知字段留 null，不用计划值冒充实际结果。更新前重读，保留原操作历史，原子替换；
旧回执不覆盖新发行。标识不是凭据，回执中不得写 token、私钥、完整聊天或原始错误日志。

### 两路回传与主会话接收

1. 发布代理先保存回执，再用当前协作工具的 `send_message` 向实际主会话发送
   `RELEASE_RESULT <product> <operation-id> <result> <receipt-path>` 和一段简短结果，
   最后提交相同身份的最终回答；不能只写 PR 或最后一句“已完成”。若主动消息工具不可用，
   在回执记录该限制并保留最终回答，不能声称主动消息已送达。2026-10-20 单代理验收中，
   子代理未暴露 `send_message`，但最终回答已自动送达运行中的主会话；这只证明该接收路径，
   不证明空闲唤起。
2. 主会话收到任一路结果后核对回执和远端关键证据，以 operation ID 与结果阶段去重，
   先向用户报告“Beta 可体验/正式可更新/失败/需处理”及下一步。新事件应在当前安全边界处理，
   不要求用户再查询；正在处理另一任务时保留事件，不打断正在发生的写操作。
3. `send_message` 返回成功只说明工具接受消息，不等于空闲主会话已自动唤起或用户已看到。
   当前尚未证明主会话结束回合后能自动继续；不得承诺即时唤醒。未确认接收的回执保持未接收，
   主会话下次进入或继续发布时优先检查。需要等待结果时可使用可被用户新输入打断的原生等待，
   不用 shell sleep、频繁查询或额外模型轮询伪造后台服务。发布飞书通知仍关闭。
4. 主会话实际核实后记录 `acknowledged_at`；确已向用户发出该阶段结果才记录
   `reported_to_user_at`，不能在派发时预写成功。重复消息不重复发布或报告。
5. 交接后用受支持的 `close_agent` 或等效生命周期工具关闭该代理，记录返回结果；
   原代理仍可用且马上有已授权下一阶段时可复用，等待用户体验则收尾关闭。
   当前工具若没有关闭接口，记录 `close_unavailable`，保留恢复材料，不能把 interrupt、
   归档、任务 completed 或数据库 open 状态当成资源释放证明。代理不可恢复时，先核实原写入
   已停止、CI 无冲突，再从回执创建一个替代代理；无法核实时报告阻塞。

发布代理只用 shell、Git/GitHub 和制品校验工具；不启动应用、Computer Use 或无关 MCP。
当前 spawn 接口没有每代理 MCP 裁剪选项，不擅自改全局 MCP/沙箱配置。资源验证只观察同一
app-server PID 的数字 FD 和子进程在启动前、运行中、结束及关闭后的变化；进程重启后
不能直接比较，不以元数据 open 数量或一次采样断言泄漏，也不自动 kill 共享后台或提高限额。

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
5. 核对 prerelease tag、目标 commit、归档、SHA 和 `omcli update --beta` 入口。完成或失败后按上面的协议保存回执、主动回传并交接；不能把自然结束视为已关闭。

用户可运行 `omcli update --beta` 安装最新候选。正式 `omcli update`、GitHub
latest 和 Homebrew 仍只读取稳定 Release。

## 正式提升（原发布代理优先）

用户明确批准具体 beta tag 及其 SHA-256 后才开始：

1. 使用新的独立 worktree，锁定用户批准的 beta tag 和 SHA-256，不以“最新 beta”或重新读取出的摘要替代用户批准值。
2. 保留用户批准的候选 commit，优先以普通非强推 fast-forward 将它送入远端默认分支；不得关闭或绕过分支保护，也不 squash 或 rebase 已批准候选。写入前重新读取远端默认分支、版本 PR、所需 CI 和保护规则，确认候选尚未被取代、批准的 tag/commit/SHA 未变，且默认分支 HEAD 是候选的祖先；当前单一版本提交通常要求 HEAD 正好是候选父提交。在独立 worktree 中执行 `git push origin <完整候选 SHA>:refs/heads/<默认分支>`，不使用 `--force`。若远端已包含候选则只核验，不重复推进；分叉、并发更新、保护规则拒绝或其他校验失败时停止并重新读取，不自动改规则、换候选或重新打包。推送后回读默认分支包含原候选，并确认版本 PR 已合并后再提升。
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
