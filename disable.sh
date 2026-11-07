#!/bin/bash
set -eu
PKG_DIR=$(cd "$(dirname "$0")" && pwd)
. "$PKG_DIR/lifecycle.sh"
if [ "${DRY_RUN:-0}" = 1 ]; then echo "DRY_RUN：将停止服务并恢复允许休眠；未写入任何文件"; exit 0; fi
begin
stop_service
if [ "$REAL" = 1 ]; then
  pmset -a disablesleep 0
  [ "$(read_disabled)" = 0 ] || { echo "恢复允许休眠未成功，拒绝报告关闭完成" >&2; exit 1; }
fi
if [ -f "$BIN" ]; then cp -p "$BIN" "$BIN.disabled-$(date +%Y%m%dT%H%M%S)-$$"; fi
rm -f "$BIN" "$PLIST" "$MODE" "$STATE"
if [ "$REAL" = 1 ]; then ! loaded || { echo "服务仍已加载" >&2; exit 1; }; fi
committed=1
echo "关闭完成：服务已卸载，系统允许休眠。空闲熄屏时间等原有设置保持原样。"
