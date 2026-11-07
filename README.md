# lid-guard-power —— MacBook 合盖电源策略（可开关）

> 这是一个 macOS 电源策略小工具：让 MacBook 在**插电合盖**时保持运行并锁屏（后台任务不中断），
> 在**电池合盖**时正常休眠。开启/关闭都是一条命令。
> 详细步骤见 [使用说明.md](使用说明.md)，验证记录见 [EVIDENCE.md](EVIDENCE.md)。

让 MacBook Air/Pro 达到你要的三条行为：

| 场景 | 行为 |
|---|---|
| 插电 + 合盖 | 保持系统运行、熄屏并锁定会话（需要密码或 Touch ID 解锁），后台任务继续跑 |
| 电池 + 合盖 | 整机休眠，开盖后唤醒并解锁 |
| 开盖 | 正常使用 |

通过系统自带的 `pmset disablesleep`（插电禁止休眠）+ `pmset displaysleepnow`（熄屏锁定）实现，
不修改电池/插电的空闲熄屏与休眠时间，也不改动 macOS 自身的温控设置。

## 使用方法（详细步骤见 [使用说明.md](使用说明.md)）

## 使用

```sh
bash status.sh                 # 查看当前状态（不需要管理员权限）
sudo bash enable.sh            # 开启
sudo bash disable.sh           # 关闭，恢复系统默认行为
```

macOS 用户可以直接双击 `enable.command` / `disable.command` / `status.command`，
前两个会弹出系统管理员认证窗口。

> 如果解压后双击没反应（提示权限不足），先执行一次 `chmod +x *.command *.sh`。

## 包内文件

| 文件 | 说明 |
|---|---|
| `lid-guard.sh` | 守护进程脚本本体（每秒轮询供电与合盖状态） |
| `enable.sh` | 安装脚本、写入 LaunchDaemon、启动并校验 |
| `disable.sh` | 停止服务、恢复正常休眠、移除文件 |
| `status.sh` | 查看供电/合盖/锁定状态与最近日志 |
| `tests/test_policy.py` | 21 个隔离场景的回归测试，不触碰真实电源设置 |

`enable.sh` 会把已存在的 `/usr/local/bin/lid-guard.sh` 备份为 `lid-guard.sh.bak-<时间戳>`；
`disable.sh` 会把脚本移走而不是直接删除，想恢复可以手动移回并重新 `enable.sh`。

## 回归测试

```sh
python3 tests/test_policy.py ./lid-guard.sh
```

macOS 大版本升级后建议重跑一次，确认合盖策略没有随系统行为变化而失效。

## 已知限制

- 这是每秒轮询的定制策略，插拔电源的识别存在最多约 1 秒延迟。
- `disablesleep` 是系统级开关：插电期间手动合盖以外的手动睡眠也会被禁止。
- 读取传感器与执行系统调用无法原子化，极端时序下可能有边界情况。
- 未在长时间满载合盖的场景下实测；无风扇机型合盖持续运行时请保持通风，不要放进包里。
- 不承诺绝对没有缺陷。
