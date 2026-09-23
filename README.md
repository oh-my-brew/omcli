# omcli

`omcli` 将多个 macOS 小工具合并到一个命令中：

```sh
omcli lockscreen
omcli ncdu
omcli ncdu dump
omcli ncdu read
omcli xcodex
```

不带参数运行 `omcli` 只显示帮助，不会修改系统。项目仅支持运行 macOS
的 Apple Silicon（`arm64`）设备。

## 安装

```sh
brew install oh-my-brew/tap/omcli
```

## 命令

### 锁屏

`omcli lockscreen` 立即锁定 macOS 屏幕。

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

### active writer 应急恢复

```sh
omcli xcodex
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

测试不会真实锁屏、扫描磁盘、打开 ncdu 界面或终止 writer 进程。路由测试会
替换外部执行边界。锁屏辅助程序只会被编译并检查是否为 Mach-O，不会运行。

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

omcli 集成代码和 `xcodex` 使用 [MIT License](LICENSE)。从 `omzcj/dotfiles`
迁移的 ncdu 封装，以及从 `omzcj/lockscreen` 迁移的锁屏辅助程序，继续使用
[Apache License 2.0](LICENSE-APACHE)；组件说明见 [NOTICE](NOTICE)。
