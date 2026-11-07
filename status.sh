#!/bin/bash
# lid-guard-power: 查看当前状态
LABEL=co.user.lid-guard
ETC=/usr/local/etc

if launchctl print system/$LABEL >/dev/null 2>&1; then
  echo "服务：运行中  $(launchctl print system/$LABEL | awk '/pid =/{print "pid=" $3;exit}')"
else
  echo "服务：未运行（合盖行为由系统默认处理）"
fi

if [ -r "$ETC/lid-guard.state" ]; then
  echo "状态：$(cat "$ETC/lid-guard.state")"
  echo "字段说明：power=ac|battery 供电；lid=open|closed 合盖；disabled=1 表示禁止系统休眠（插电保持运行）；locked=1 表示会话已锁定"
fi

echo
echo "当前电源设置："
pmset -g custom | sed -n '1,40p'
echo
echo "锁屏策略：$(sysadminctl -screenLock status 2>&1 | tail -1)"

echo
echo "最近日志："
if [ -r /var/log/lid-guard.log ]; then tail -8 /var/log/lid-guard.log; else echo "（无日志）"; fi
