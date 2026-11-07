# lid-guard-power v1.1.0

给 MacBook 配置可关闭的合盖电源策略：**插电合盖保持运行并请求熄屏锁定，电池合盖休眠**。
后台任务可在插电合盖时继续执行。不是 macOS 状态栏插件，无需安装第三方运行时。

| 场景 | 行为 |
|---|---|
| 插电、合盖 | 禁止系统休眠，请求显示器休眠；检查会话锁定信号并在未确认时重试 |
| 电池、合盖 | 恢复允许休眠并请求整机睡眠 |
| 开盖 | 正常交互；插电期间仍禁止系统休眠 |

## 下载与使用

从 [Releases](https://github.com/HammerTech-Z/lid-guard-power/releases/latest) 下载 ZIP，解压后保留完整文件夹。
双击 `enable.command` 开启、`disable.command` 关闭、`status.command` 查看状态。
安装和关闭需要你在 macOS 系统窗口中输入管理员密码。

也可以交给 Mac 上能执行本地 shell 的 agent harness，运行：

```bash
bash install-for-agent.sh --check
bash install-for-agent.sh --install
```

先把终端目录切换到解压后的文件夹。`--check` 只读；无参数等同 `--install`。
卸载使用 `bash install-for-agent.sh --uninstall`。安装授权不能由 agent 替你输入密码。
无图形登录会话或 harness 沙箱不允许执行 `osascript` 时，请在本机终端运行命令。

**安装前提：**系统设置 → 锁定屏幕 → 在屏幕保护程序启动或显示器关闭后要求输入密码 → **立即**。
安装器会核对该设置，无法确认时拒绝安装；本工具不会修改密码策略。

详细步骤：[使用说明.md](使用说明.md)；版本变更：[CHANGELOG.md](CHANGELOG.md)；验证范围：[EVIDENCE.md](EVIDENCE.md)。

## 安全退出与升级

重复开启会升级脚本并保留旧脚本备份。安装/关闭失败会返回非零退出码并尝试恢复操作前文件、
服务加载状态和休眠开关；若恢复失败，会报告备份路径，不能当作成功。
关闭成功时会卸载服务并确认 `SleepDisabled=0`，保留 `.disabled-*` 脚本副本。
不修改原有空闲熄屏时间、电池休眠时间或 macOS 温控设置。

## 验证

安装不依赖 Python。开发回归需要 macOS 与 Python 3：

```bash
python3 tests/test_policy.py
python3 tests/test_lifecycle.py
python3 tests/test_launchers.py
python3 tests/test_status.py
```

这些测试使用隔离文件和系统调用替身，不申请管理员授权、不改真实电源设置。
通过测试不代表完成新机型的物理合盖验证。

## 限制

- 仅面向有合盖传感器的 MacBook；本次运行环境为 macOS 26.6.2，未验证所有机型与系统版本。
- 每秒轮询，检测延迟至少一个轮询周期，系统忙碌时可能更久。
- `disablesleep` 是系统级开关，插电期间手动选择“睡眠”也会被禁止；用完请关闭工具。
- 熄屏请求本身不是锁屏证明；以 `locked=1` 和实际开盖需解锁为准。系统密码策略变更后需复查。
- 不能保证断电、强制终止或系统命令持续失败时都能自动恢复；其他电源工具可能覆盖本工具设置。
- 无长时间满载合盖测试；保持通风，不要放进包里运行。不承诺绝对零缺陷。
