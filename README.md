# omcli

`omcli` 将多个 macOS 小工具合并到一个命令中：

```sh
omcli lockscreen
omcli lockscreen status
omcli ncdu
omcli ncdu dump
omcli ncdu read
omcli sidecar
omcli sidecar connect
omcli sidecar disconnect
omcli codex
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
- `omcli ncdu dump` 扫描启动卷并生成 `~/.ncdu.<时间戳>`。扫描排除
  `System`、`Volumes` 和 `~/.Trash`，线程数取自当前设备的
  `sysctl hw.logicalcpu`。
- `omcli ncdu read [FILE]` 显示指定快照的项目数和占比。省略 `FILE` 时，
  自动选择数字时间戳最大的 `~/.ncdu.<时间戳>` 文件。

示例：

```sh
omcli ncdu dump
omcli ncdu read
omcli ncdu read ~/.ncdu.1788940800
```

`dump` 会输出快照路径和耗时，不覆盖已有快照。自动选择快照时只接受文件名
为 `.ncdu.` 加纯数字时间戳的普通文件。

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

### active writer 应急恢复

```sh
omcli codex
```

该命令查找所有正在持有 `~/.codex/thread-writer-locks` 中文件的进程，去重后
向它们发送 `SIGTERM`。没有持有进程时直接成功退出，不发送信号。

这是明确出现 `active writer` 或会话占用时的人工应急命令，可能终止 ChatGPT
Desktop、Codex 或正在生成的响应，不应自动执行，也不能代替正确的多设备连接
方式。

## 开发

```sh
make build
sh tests/test.sh
```

测试不会真实锁屏、扫描磁盘、打开 ncdu 界面、连接随航设备或终止 writer
进程。路由测试会替换外部执行边界。锁屏辅助程序只会被编译、检查是否为 Mach-O、
确认没有链接私有框架，并执行只读的 `status` 子命令；随航辅助程序只会被编译并
检查是否为 Mach-O。两者都不会被请求执行真正的动作。

## 发布

修改 `VERSION` 后推送到 `main`。Release workflow 会执行隔离测试，并将
`omcli-VERSION.tar.gz` 发布到名为 `vVERSION` 的 GitHub Release。发布自动化
使用 `oh-my-infra/brew-ci`，发布结果位于 `oh-my-brew/omcli`。
Release 包含 CI 构建的 arm64 `omcli-lockscreen`，Homebrew 安装不要求目标机器
使用本地 Command Line Tools 重新编译该辅助程序。

手动运行 Release workflow 默认只验证和打包，不发布：`publish=false` 使用
现有版本运行验证并检查两次打包结果一致，不修改 `VERSION` 或创建 tag/release。
显式选择 `publish=true` 才会发布；现有 main 源码 push 仍按原规则自动发布。

## 许可证

omcli 集成代码和 `codex` 使用 [MIT License](LICENSE)。随航 helper 基于
[SidecarLauncher](https://github.com/Ocasio-J/SidecarLauncher) 修改，其 MIT
许可证见 [LICENSE-SIDECARLAUNCHER](LICENSE-SIDECARLAUNCHER)。从
`omzcj/dotfiles` 迁移的 ncdu 封装，以及从 `omzcj/lockscreen` 迁移的锁屏
辅助程序，继续使用 [Apache License 2.0](LICENSE-APACHE)；组件说明见
[NOTICE](NOTICE)。
