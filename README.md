# omcli

`omcli` 将多个 macOS 小工具合并到一个命令中：

```sh
omcli lockscreen
omcli lockscreen status
omcli ncdu
omcli ncdu dump
omcli ncdu read
omcli ncdu list
omcli ncdu prune
omcli sidecar
omcli sidecar connect
omcli sidecar disconnect
omcli iphone ssh
omcli codex recover
omcli update --check
omcli update
omcli update --beta
```

不带参数运行 `omcli` 只显示帮助，不会修改系统。项目仅支持运行 macOS
的 Apple Silicon（`arm64`）设备。

## 安装

```sh
brew install oh-my-brew/tap/omcli
```

## 命令

### 锁屏

```sh
omcli lockscreen
omcli lockscreen --method agent
omcli lockscreen status
omcli lockscreen doctor
```

- `omcli lockscreen` 使用 `auto`：图形会话先尝试 `direct`，后台或 SSH 会话先
  尝试临时 GUI `agent`；未确认锁屏时，仅在密码延迟为“立即”时回退到
  `display-sleep`。每种方法都会在 3 秒内回读系统锁屏标志，只有确认已锁屏才成功。
- `omcli lockscreen --method METHOD` 显式选择 `auto`、`direct`、`agent`、
  `display-sleep` 或 `hotkey`。`hotkey` 使用原生 CoreGraphics 发送 Apple 官方的
  Control-Command-Q，仅显式调用，不进入 `auto`，且需要辅助功能权限。
- `omcli lockscreen status` 只读当前状态，输出 `locked` 或 `unlocked`。
- `omcli lockscreen doctor` 只读当前会话、控制台用户、GUI agent、密码延迟和
  各原生方法的能力信息，不弹出权限请求。`gui_domain=available` 只表示图形会话
  存在；是否允许临时载入 agent 仍以真正调用结果为准。
- 退出码：`0` 已锁屏，`1` 未锁屏，`2` 参数错误，`3` 无法读取锁屏状态或没有
  可用的锁定机制。`omcli lockscreen` 不再无条件返回成功。

`direct` 在运行时用 `dlopen` 解析 Apple 私有 `login` 框架中的
`SACLockScreenImmediate`，因此不静态链接私有框架。`agent` 临时将同一动作加载到
当前控制台用户的 GUI launchd domain，完成或超时后立即 bootout 并删除临时文件；
异常遗留会在下次调用时恢复。`display-sleep` 使用 `pmset displaysleepnow`，并先
确认系统配置为显示器关闭后立即要求密码。所有系统调用返回后仍须观察到
`IOConsoleLocked` 才算成功。

### ncdu 快照

- `omcli ncdu` 和 `omcli ncdu help` 只显示帮助，不扫描磁盘。
- `omcli ncdu dump [DIRECTORY]` 扫描指定目录；省略目录时扫描启动卷。只有扫描
  `/` 时才排除 `System`、`Volumes` 和 `~/.Trash`。线程数取自当前设备的
  `sysctl hw.logicalcpu`，不使用固定或过量线程数。
- 快照按规范化目标路径分组，存放在
  `${XDG_STATE_HOME:-$HOME/.local/state}/omcli/ncdu/<名称>-<路径哈希>/`，文件名为
  `YYYYMMDD-HHMMSS-NNN.ncdu`。目标目录权限为 `700`，快照使用私有 umask；扫描先
  写同目录临时文件，成功后再原子重命名。
- `omcli ncdu read` 打开所有目标中最新的快照；传入目录时打开该目标的最新快照；
  传入普通文件时打开明确指定的快照。
- `omcli ncdu list` 按创建时间倒序列出受管快照的时间、大小、目标和完整路径。
- `omcli ncdu prune` 每个扫描目标分别保留最近3份；`--keep N` 修改保留数量，
  `--dry-run` 只预览。它只处理符合受管命名规则的快照，不处理其他文件。

示例：

```sh
omcli ncdu dump
omcli ncdu dump ~/Code
omcli ncdu read
omcli ncdu read ~/Code
omcli ncdu list
omcli ncdu prune --dry-run
omcli ncdu prune --keep 10
```

`dump` 会输出规范化后的扫描目标、快照路径和耗时。同一秒生成多份时递增 `NNN`。
旧的 `~/.ncdu.<时间戳>` 不会被读取、列出、迁移或清理。

### 随航（Sidecar）

```sh
omcli sidecar list
omcli sidecar connect [DEVICE]
omcli sidecar disconnect [DEVICE]
```

- `omcli sidecar` 和 `omcli sidecar help` 只显示帮助，不改变显示器连接。
- `list` 列出当前可发现的随航设备。
- `connect DEVICE` 连接指定 iPad；省略名称时，只有一台可发现设备才会自动选择。
- `disconnect DEVICE` 断开指定 iPad；省略名称时，只有一台已连接设备会自动选择。
- 没有已连接设备时，无参数 `disconnect` 直接成功退出。
- 发现或连接多台设备时必须明确提供名称；omcli 不承诺 macOS 支持同时使用
  多台 iPad 作为随航显示器。

该功能使用 Apple 未公开的 `SidecarCore` 私有框架，不需要通过辅助功能权限点击
控制中心，但可能在 macOS 升级后失效。Mac 与 iPad 仍须满足 Apple 的随航要求，
包括使用同一 Apple 账户；无线连接还要求开启蓝牙、Wi-Fi 和接力。iPad 锁定或
休眠时可能可被发现但无法连接。

### iPhone USB SSH

```sh
omcli iphone ssh
omcli iphone ssh uname -a
```

`omcli iphone ssh` 使用 `iproxy` 临时建立 `localhost:2222 -> iPhone:22`
的 USB 转发，然后通过现有的 `iphone.jb` SSH 配置连接设备。SSH 退出或命令被
中断时，只终止本次启动的 `iproxy` 并删除临时日志，不安装或启动常驻服务。

本地端口 2222 已被占用、没有连接设备、`iproxy` 提前退出或三秒内没有建立
转发时，命令会失败并保留原有进程。用户名、密钥及其他 SSH 选项继续由
`~/.ssh/config` 中的 `iphone.jb` 管理。

### active writer 应急恢复

```sh
omcli codex recover
```

`omcli codex` 和 `omcli codex help` 只显示帮助。`recover` 查找所有正在持有
`~/.codex/thread-writer-locks` 中文件的进程，去重后
向它们发送 `SIGTERM`。没有持有进程时直接成功退出，不发送信号。

这是明确出现 `active writer` 或会话占用时的人工应急命令，可能终止 ChatGPT
Desktop、Codex 或正在生成的响应，不应自动执行，也不能代替正确的多设备连接
方式。

## 开发

```sh
make build
sh tests/test.sh
```

测试不会真实锁屏、扫描磁盘、打开 ncdu 界面、连接随航设备、连接 iPhone 或终止
writer 进程。路由测试会替换外部执行边界。锁屏辅助程序只会被编译、检查是否为 Mach-O、
确认没有链接私有框架，并执行只读的 `status` 子命令；随航辅助程序只会被编译并
检查是否为 Mach-O。两者都不会被请求执行真正的动作。

## 发布

功能代码进入 `main` 且源码 CI 通过后，主会话启动独立 Beta Release subagent 后即可继续响应。
subagent 在独立 worktree 中创建版本候选和 PR，并从固定 commit 生成
`vVERSION-beta.N` prerelease。用户确认候选后，另一个 Promote subagent 校验并将
完全相同的 tar.gz 与 SHA 提升为 `vVERSION` 正式 Release，不重新打包。
Release 包含 CI 构建的 arm64 原生 helpers，Homebrew 安装不要求目标机器使用本地
Command Line Tools 重新编译。

beta 失败不会自动提升，正式提升必须由用户明确批准具体 beta tag 及其 SHA-256。
Promote 会以 GitHub 远端默认分支的准确 HEAD 验证候选已合入，并要求候选校验文件、
资产实际摘要和批准值三者一致。发布过程不发送飞书通知。

完整的产品发行及其与 Homebrew 的边界见 [RELEASING.md](RELEASING.md)。

## 自更新

`omcli update --check` 只检查最新稳定 Release；`omcli update` 校验 SHA-256、归档路径、
版本和原生 helpers 后，将新版本原子切换到 `~/.local/share/omcli/current`。Homebrew Cellar
保持不变，之后执行 Homebrew 安装的 `omcli` 会自动委派给较新的用户级版本。

`omcli update --beta` 安装最新的 prerelease 候选，`--check-beta` 只检查。候选 tag
单独记录，因此同一正式版本号的 `beta.1`、`beta.2` 仍能依次更新。普通
`omcli update`、GitHub latest 和 Homebrew 不读取 beta；正式版发布后，普通更新会把
同版本 beta 切回稳定通道。

`omcli update --reset` 删除用户级覆盖并恢复使用 Homebrew 版本。临时设置
`OMCLI_USE_BUNDLED=1` 可对单次命令绕过用户级版本。更新目录只保留当前版本和前一个版本。

## 许可证

omcli 集成代码、iPhone USB 命令和 `codex` 使用 [MIT License](LICENSE)。随航 helper 基于
[SidecarLauncher](https://github.com/Ocasio-J/SidecarLauncher) 修改，其 MIT
许可证见 [LICENSE-SIDECARLAUNCHER](LICENSE-SIDECARLAUNCHER)。从
`omzcj/dotfiles` 迁移的 ncdu 封装，以及从 `omzcj/lockscreen` 迁移的锁屏
辅助程序，继续使用 [Apache License 2.0](LICENSE-APACHE)；组件说明见
[NOTICE](NOTICE)。
