#!/bin/bash
# lid-guard-power: 开启（安装并启动合盖电源策略守护进程）
set -eu
PKG_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT="${LIDGUARD_ROOT:-}"
DRY_RUN="${DRY_RUN:-0}"
LABEL=co.user.lid-guard

if [ -n "$ROOT" ]; then
  BIN="$ROOT/usr/local/bin/lid-guard.sh"; PLIST="$ROOT/Library/LaunchDaemons/$LABEL.plist"
  ETC="$ROOT/usr/local/etc"; LOG="$ROOT/var/log/lid-guard.log"; REAL=0
else
  BIN=/usr/local/bin/lid-guard.sh; PLIST=/Library/LaunchDaemons/$LABEL.plist
  ETC=/usr/local/etc; LOG=/var/log/lid-guard.log; REAL=1
  [ "$(id -u)" = 0 ] || { echo "需要管理员权限：sudo bash $0" >&2; exit 1; }
fi

run() { echo "+ $*"; [ "$DRY_RUN" = 1 ] || "$@"; }

src="$PKG_DIR/lid-guard.sh"
[ -f "$src" ] || { echo "包内缺少 lid-guard.sh" >&2; exit 1; }
bash -n "$src"

echo "== 1/5 准备目录 =="
run mkdir -p "$(dirname "$BIN")" "$(dirname "$PLIST")" "$ETC" "$(dirname "$LOG")"

echo "== 2/5 安装脚本（会备份旧版本）=="
if [ -f "$BIN" ]; then
  backup="$BIN.bak-$(date +%Y%m%dT%H%M%S)"
  run cp -p "$BIN" "$backup"
  echo "   已备份到 $backup"
fi
run install -m 755 "$src" "$BIN"

echo "== 3/5 写入配置 =="
run sh -c "printf 'on\n' > '$ETC/lid-guard.mode'"

plist_tmp="$PKG_DIR/.co.user.lid-guard.plist.$$"
cat > "$plist_tmp" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${BIN}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>10</integer>
    <key>ProcessType</key>
    <string>Background</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
    <key>StandardOutPath</key>
    <string>${LOG}</string>
    <key>StandardErrorPath</key>
    <string>${LOG}</string>
</dict>
</plist>
PLISTEOF
if [ "$REAL" = 1 ]; then
  run install -o root -g wheel -m 644 "$plist_tmp" "$PLIST"
else
  run cp "$plist_tmp" "$PLIST"
fi
rm -f "$plist_tmp"

echo "== 4/5 启动服务 =="
if [ "$REAL" = 1 ]; then
  run launchctl bootout system/$LABEL || true
  run launchctl bootstrap system "$PLIST"
  run launchctl kickstart -k system/$LABEL
else
  echo "   (测试根目录，跳过 launchctl)"
fi

echo "== 5/5 校验 =="
if [ "$REAL" = 1 ]; then
  ready=0
  for i in 1 2 3 4 5 6 7 8 9 10; do
    pid=$(launchctl print system/$LABEL 2>/dev/null | awk '/pid =/{print $3;exit}')
    if [ -n "$pid" ] && grep -q "pid=$pid " "$ETC/lid-guard.state" 2>/dev/null && grep -q 'version=v5.0-normal' "$ETC/lid-guard.state" 2>/dev/null; then ready=1; break; fi
    sleep 1
  done
  [ "$ready" = 1 ] || { echo "守护进程未在 10 秒内发布状态，请检查 $LOG" >&2; exit 1; }
  echo "   已运行 pid=$pid"
else
  echo "   (测试根目录，跳过运行校验)"
fi

echo
echo "开启完成。当前策略："
echo "  插电 + 合盖  -> 保持运行、熄屏并锁定（需要密码解锁）"
echo "  电池 + 合盖  -> 整机休眠"
echo "  开盖         -> 正常使用"
echo
echo "查看状态： bash $PKG_DIR/status.sh"
echo "关闭      ： sudo bash $PKG_DIR/disable.sh"
