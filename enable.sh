#!/bin/bash
set -eu
PKG_DIR=$(cd "$(dirname "$0")" && pwd)
. "$PKG_DIR/lifecycle.sh"
if [ "${DRY_RUN:-0}" = 1 ]; then echo "DRY_RUN：将安装 $BIN 和 ${PLIST}；未写入任何文件"; exit 0; fi
[ -f "$PKG_DIR/lid-guard.sh" ] || { echo "包内缺少 lid-guard.sh" >&2; exit 1; }
/bin/bash -n "$PKG_DIR/lid-guard.sh"
preflight
begin
stop_service
mkdir -p "$(dirname "$BIN")" "$(dirname "$PLIST")" "$ETC" "$(dirname "$LOG")"
if [ -f "$BIN" ]; then cp -p "$BIN" "$BIN.bak-$(date +%Y%m%dT%H%M%S)-$$"; fi
# Replace the inode, rather than writing through a pre-existing symbolic link.
install -m 755 "$PKG_DIR/lid-guard.sh" "$SNAP/new-script"
if [ "$REAL" = 1 ]; then chown root:wheel "$SNAP/new-script"; fi
mv -f "$SNAP/new-script" "$BIN"
printf 'on\n' > "$SNAP/new-mode"
chmod 644 "$SNAP/new-mode"
mv -f "$SNAP/new-mode" "$MODE"
# XML escaping matters for test roots containing spaces, apostrophes or ampersands.
xml() { printf '%s' "$1" | sed 's/\&/\&amp;/g;s/</\&lt;/g;s/>/\&gt;/g'; }
cat > "$SNAP/new-plist" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$LABEL</string>
<key>ProgramArguments</key><array><string>$(xml "$BIN")</string></array>
<key>RunAtLoad</key><true/>
<key>KeepAlive</key><true/>
<key>ThrottleInterval</key><integer>10</integer>
<key>ProcessType</key><string>Background</string>
<key>StandardOutPath</key><string>$(xml "$LOG")</string>
<key>StandardErrorPath</key><string>$(xml "$LOG")</string>
</dict></plist>
PLISTEOF
plutil -lint "$SNAP/new-plist"
chmod 644 "$SNAP/new-plist"
if [ "$REAL" = 1 ]; then chown root:wheel "$SNAP/new-plist"; fi
mv -f "$SNAP/new-plist" "$PLIST"
rm -f "$STATE"
if [ "$REAL" = 1 ]; then
  launchctl bootstrap system "$PLIST"
  ready=0
  for i in 1 2 3 4 5 6 7 8 9 10; do
    pid=$(launchctl print "system/$LABEL" 2>/dev/null | awk '/pid =/{print $3;exit}')
    if [ -n "$pid" ] && grep -Fq "pid=$pid " "$STATE" 2>/dev/null && grep -Fq 'version=1.1.0 mode=on ' "$STATE" 2>/dev/null; then
      state=$(cat "$STATE")
      case "$state" in
        *power=ac*lid=open*disabled=1*|*power=ac*lid=closed*disabled=1*locked=1*|*power=battery*lid=open*disabled=0*|*power=battery*lid=closed*disabled=0*) ready=1; break ;;
      esac
    fi
    sleep 1
  done
  [ "$ready" = 1 ] || { echo "服务未在 10 秒内就绪，请检查 $LOG" >&2; exit 1; }
fi
committed=1
echo "开启完成：v1.1.0。插电合盖保持运行并请求熄屏锁定；电池合盖休眠。"
echo "请用 bash install-for-agent.sh --check 查看实际状态，并完成两轮合盖实测。"
