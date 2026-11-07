#!/bin/bash
# Read-only preflight and runtime report. Exit 1 means an attention item was found.
set -u
PATH=/usr/bin:/bin:/usr/sbin:/sbin
LABEL=co.user.lid-guard
ETC=/usr/local/etc
ok=0
report=$(launchctl print "system/$LABEL" 2>/dev/null) || report=
pid=$(printf '%s\n' "$report" | awk '/pid =/{print $3;exit}')
if [ -n "$pid" ] && printf '%s\n' "$report" | grep -q 'state = running'; then
  echo "服务：运行中 pid=$pid"
  if [ -r "$ETC/lid-guard.state" ] && grep -q "pid=$pid " "$ETC/lid-guard.state"; then
    age=$(( $(date +%s) - $(stat -f %m "$ETC/lid-guard.state") ))
    echo "状态（${age}秒前）：$(cat "$ETC/lid-guard.state")"
    if [ "$age" -gt 15 ] || [ "$age" -lt 0 ]; then echo "警告：状态可能已过期"; ok=1; fi
    if ! grep -Fq 'version=1.1.0 ' "$ETC/lid-guard.state"; then echo "提示：运行版本不是 1.1.0，需要升级"; ok=1; fi
    state=$(cat "$ETC/lid-guard.state")
    case "$state" in
      *mode=on*power=ac*lid=open*disabled=1*|*mode=on*power=ac*lid=closed*disabled=1*locked=1*|*mode=on*power=battery*lid=open*disabled=0*|*mode=on*power=battery*lid=closed*disabled=0*) : ;;
      *) echo "警告：策略状态尚未达到预期，或锁定未确认"; ok=1 ;;
    esac
  else
    echo "警告：未找到与当前进程匹配的状态，不能确认策略已生效"; ok=1
  fi
elif [ -n "$report" ]; then
  echo "服务：已加载但没有运行进程，需检查日志"; ok=1
else
  echo "服务：未安装或未加载"
fi
echo "当前供电："
pmset -g ps || ok=1
echo "当前合盖与休眠开关："
lid=$(ioreg -n IOPMrootDomain -r -d 1 2>/dev/null | sed -n '/"AppleClamshellState"/p')
echo "${lid:-未检测到合盖传感器}"
[ -n "$lid" ] || ok=1
disabled=$(pmset -g | awk '/SleepDisabled/{print $2;exit}')
echo "SleepDisabled=${disabled:-unknown}（1=禁止系统休眠；0=允许休眠）"
case "$disabled" in 0|1) ;; *) ok=1 ;; esac
if [ -z "$pid" ] && [ "$disabled" = 1 ]; then echo "警告：没有本工具运行进程但休眠被禁用，可能有其他工具或残留设置"; ok=1; fi
policy=$(sysadminctl -screenLock status 2>&1)
echo "锁屏策略：$policy"
case "$policy" in *"screenLock delay is immediate"*) ;; *) echo "需要把熄屏后要求密码设为立即，才能满足锁屏前提"; ok=1 ;; esac
echo "当前锁定信号（Yes=已锁定；未读到不代表已锁定）："
ioreg -n Root -d 1 2>/dev/null | sed -n '/"IOConsoleLocked"/p'
echo "最近日志（只供参考，可能包含旧版记录）："
if [ -r /var/log/lid-guard.log ]; then tail -8 /var/log/lid-guard.log; else echo "（无日志）"; fi
echo "检查不会修改设置。通过不等于已完成合盖实测；不穷举检测其他电源工具。"
exit "$ok"
