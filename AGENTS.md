# omcli 工程约定

本文件适用于整个仓库。`README.md` 面向用户，`RELEASING.md` 记录产品发行流程；这里保存开发、验证和委派边界。

## 开发

- 开始前检查 Git 状态，保留用户与其他会话的修改；不要 reset、clean、stash、强推或擅自切换分支。
- 源码修改应补充隔离的自动化测试并同步用户文档。可以运行 `make build`、`sh tests/test.sh`、Shell 语法检查和其他不会改变真实系统状态的检查。
- 不在本地测试真实功能，不把开发产物安装到 Homebrew prefix。不得执行锁屏、磁盘扫描或清理、Sidecar 连接、iPhone SSH、Codex writer 恢复等有副作用的命令。
- 自动化检查通过不等于功能已经人工验证；交付时明确列出未做的运行时验证。

## 自动发行（2026-10-25 用户决定）

开发完成后立即从固定源码提交启动 `.github/workflows/beta.yml`，不等源码 CI 或人工体验确认。
同仓库、非 draft 的开发 PR 添加 `release` 标签后，后续 source 更新会自动请求新候选；
也可由仓库 writer 对本仓库分支的准确 head 派发：

```sh
gh workflow run beta.yml --ref main --field source_ref=<40位准确源码SHA>
```

- 受信任默认分支 workflow 调用固定 SHA 的 brew-ci 协调脚本，创建独立 `release/auto-<run-id>` 分支与候选 PR，不回写开发分支或本地工作树。以当前默认分支合入请求源码后分配新的 `YYYY.MM.DD.N`，候选 PR 指向准确 commit/tree。组织允许相关权限，只在这两个产品仓库启用 Actions 创建候选 PR。
- 包构建与单元/回归测试、CodeQL 快速语言扫描并行。Beta 只等包和必要分发验证，不等质量测试；Beta 可在安装体验前因 CI 已通过而自动提升。
- Beta、manifest、SHA 不可覆盖。重试已存在的 Beta 时下载原制品，不重新构建。失败保留候选与 CI 证据；修复后创建新版本，旧版本不覆盖。
- `release-state` 分支保留最新候选与版本预留。准备候选、移动 Beta feed、正式提升共用 publication concurrency；构建/测试不持有发布锁。发布前核对候选身份及开发 PR 最新 head，已取代候选不得写 feed 或正式版。
- 自动测试报告到准确候选 SHA，保留原有严格分支保护。CI 成功后以 squash 合入候选 PR，要求合入 tree 与已测试候选 tree 完全一致；有冲突或并发基线变化时停止，不绕过保护，不把不同源码当作同一候选。
- 正式版从 GitHub 下载 Beta 原制品，验证 manifest 和 SHA，然后发布相同字节；不重新构建、签名或公证。正式标签指向同 tree 的合入 commit，manifest 保留 source/candidate 身份。
- 不要求 Git 标签签名，不为此维护额外密钥；正式标签仍不可覆盖，指向受保护合入且 tree 与候选一致的 commit。应用签名、公证及更新签名不受此简化影响。
- 不再需要发布 subagent、`release-approved` 标签、人工复制候选 SHA 批准或单独 Promote 派发。失败任务可从同一 Actions run 重跑；新源码使用新请求。产品 Release 完成不等待 Tap，不升级设备，不发送飞书通知。

## 文档与接续

- 用户使用说明放 `README.md`，开发约定放本文件，发行决定与回执协议只在 `RELEASING.md` 维护；不复制 Amadeus 的个人资料或其他项目上下文。
- 开始或接续发行先核对 Actions run、release-state、候选 PR 和远端实际状态；普通开发只读取当前任务需要的内容。
- 单纯文档维护不自动启动 Beta/Promote；提交和推送遵循当前任务授权，不创建版本 tag、不调整 `VERSION`。
- 交接注明准确提交、实际检查、未验证项、阻塞及具体下一步；不要将推送成功等同于发行或真实功能验收。
