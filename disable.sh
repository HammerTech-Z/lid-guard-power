#!/bin/bash
# lid-guard-power: 关闭（停止并卸载合盖电源策略守护进程，恢复系统默认行为）
set -eu
ROOT="${LIDGUARD_ROOT:-}"
DRY_RUN="${DRY_RUN:-0}"
LABEL=co.user.lid-guard

if [ -n "$ROOT" ]; then
  BIN="$ROOT/usr/local/bin/lid-guard.sh"; PLIST="$ROOT/Library/LaunchDaemons/$LABEL.plist"
  ETC="$ROOT/usr/local/etc"; REAL=0
else
  BIN=/usr/local/bin/lid-guard.sh; PLIST=/Library/LaunchDaemons/$LABEL.plist
  ETC=/usr/local/etc; REAL=1
  [ "$(id -u)" = 0 ] || { echo "需要管理员权限：sudo bash $0" >&2; exit 1; }
fi

run() { echo "+ $*"; [ "$DRY_RUN" = 1 ] || "$@"; }

echo "== 1/4 停止服务 =="
if [ "$REAL" = 1 ]; then
  run launchctl bootout system/$LABEL || echo "   (服务本来就没运行)"
fi

echo "== 2/4 恢复正常休眠 =="
if [ "$REAL" = 1 ]; then
  run pmset -a disablesleep 0 || echo "   (disablesleep 设置失败，请手动执行 pmset -a disablesleep 0)"
fi

echo "== 3/4 移除文件 =="
if [ -f "$BIN" ]; then
  keep="$BIN.disabled-$(date +%Y%m%dT%H%M%S)"
  run mv "$BIN" "$keep"
  echo "   脚本已移至 ${keep}（如需恢复可手动移回）"
fi
if [ -f "$PLIST" ]; then run rm -f "$PLIST"; fi
for f in lid-guard.mode lid-guard.state lid-guard.maxtemp lid-guard.resume_temp lid-guard.trip_level lid-guard.pressure lid-guard.fused lid-guard.faketemp; do
  if [ -f "$ETC/$f" ]; then run rm -f "$ETC/$f"; fi
done

echo "== 4/4 校验 =="
if [ "$REAL" = 1 ]; then
  if launchctl print system/$LABEL >/dev/null 2>&1; then
    echo "服务仍在运行，请手动检查" >&2; exit 1
  fi
  state=$(pmset -g | awk '/SleepDisabled/{print $2}')
  echo "   服务已卸载，SleepDisabled=${state}（0 表示系统默认允许休眠）"
  echo "   电池/插电的空闲熄屏与休眠时间从未被本工具修改，保持系统原样"
fi
echo
echo "关闭完成，机器行为已恢复系统默认。"
