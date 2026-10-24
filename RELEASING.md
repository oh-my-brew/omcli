# omcli 自动候选与正式发行

## 自动发行（2026-10-25 用户决定）

开发完成后立即从固定源码提交启动 `.github/workflows/beta.yml`，不等源码 CI 或人工体验确认。
同仓库、非 draft 的开发 PR 添加 `release` 标签后，后续 source 更新会自动请求新候选；
也可由仓库 writer 对已有同仓库、非 draft 开发 PR 的准确 head 派发：

```sh
gh workflow run beta.yml --ref main --field source_ref=<40位准确源码SHA>
```

- 受信任默认分支 workflow 调用固定 SHA 的 brew-ci 协调脚本，在独立 `release/auto-<run-id>` 分支准备版本候选，再以普通非强推快进追加到现有开发 PR 分支；不修改本地工作树。以当前默认分支合入请求源码后，分配新的 `YYYY.MM.DD.N`，开发 PR 指向准确候选 commit/tree。组织禁止 Actions 建 PR 的策略保持不变。
- 包构建与单元/回归测试、CodeQL 快速语言扫描并行。Beta 只等包和必要分发验证，不等质量测试；Beta 可在安装体验前因 CI 已通过而自动提升。
- Beta、manifest、SHA 不可覆盖。重试已存在的 Beta 时下载原制品，不重新构建。失败保留候选与 CI 证据；修复后创建新版本，旧版本不覆盖。
- `release-state` 分支保留最新候选与版本预留。准备候选、移动 Beta feed、正式提升共用 publication concurrency；构建/测试不持有发布锁。发布前核对候选身份及开发 PR 最新 head，已取代候选不得写 feed 或正式版。
- 自动测试报告到准确候选 SHA，保留原有严格分支保护。CI 成功后以 squash 合入候选 PR，要求合入 tree 与已测试候选 tree 完全一致；有冲突或并发基线变化时停止，不绕过保护，不把不同源码当作同一候选。
- 正式版从 GitHub 下载 Beta 原制品，验证 manifest 和 SHA，然后发布相同字节；不重新构建、签名或公证。正式标签指向同 tree 的合入 commit，manifest 保留 source/candidate 身份。
- Git 标签使用每仓库独立 SSH 签名密钥，私钥在 `RELEASE_SIGNING_KEY` Actions Secret，本机恢复入口为 login Keychain 的 service `github-fast-release-signing`、account `oh-my-brew/omcli`。公钥固定在默认分支 `.github/release-signers`，以 `git verify-tag` 验证。与旧版依赖 GitHub 账号签名登记的验证方式不同，新的签名信任锚是仓库公钥；GitHub 账号未登记该公钥时 UI 可能显示 Unverified，但流水线必须通过固定公钥的密码学验证。
- 不再需要发布 subagent、`release-approved` 标签、人工复制候选 SHA 批准或单独 Promote 派发。失败任务可从同一 Actions run 重跑；新源码使用新请求。产品 Release 完成不等待 Tap，不升级设备，不发送飞书通知。

## 构建与安装

快速路径只执行 `make build`、确定性归档与 SHA 记录，不执行真实功能或等待测试。
质量路径独立执行 `make build && sh tests/test.sh`；测试构建与最终发行构建用途不同，
正式制品只构建一次。`omcli update --beta` 安装最新候选，`omcli update` 使用稳定版本。
Homebrew Cellar 保持只读；不得把构建包安装到本机 prefix 作为发行验证。

## 验收

记录 source/candidate/merged commit、对应 tree、PR、Actions run、Beta/正式标签和资产 SHA。
验证 Beta 发布不依赖质量 job、质量失败不能发布正式版、旧候选不能发布、原制品同 SHA，
以及重试不覆盖发布内容。自动化检查不等于锁屏、Sidecar 等真实功能已人工验证。
