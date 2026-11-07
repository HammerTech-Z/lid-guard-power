#!/bin/bash
# Noninteractive harness entry: only --check is read-only; install prompts the human.
set -eu
PATH=/usr/bin:/bin:/usr/sbin:/sbin
PKG_DIR=$(cd "$(dirname "$0")" && pwd)
[ "$(uname -s)" = Darwin ] || { echo "仅支持 macOS" >&2; exit 1; }
[ "$#" -le 1 ] || { echo "用法：bash install-for-agent.sh [--check|--install|--uninstall]" >&2; exit 2; }
case "${1:---install}" in
  --check) exec /bin/bash "$PKG_DIR/status.sh" ;;
  --install) action=enable ;;
  --uninstall) action=disable ;;
  *) echo "用法：bash install-for-agent.sh [--check|--install|--uninstall]" >&2; exit 2 ;;
esac
if [ "$(id -u)" = 0 ]; then
  exec /usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin /bin/bash "$PKG_DIR/$action.sh"
fi
echo "请在 Mac 上的系统管理员认证窗口中确认；取消或失败会返回非零状态。"
exec /usr/bin/osascript - "$PKG_DIR/$action.sh" <<'APPLESCRIPT'
on run argv
    set scriptPath to item 1 of argv
    do shell script "/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin /bin/bash " & quoted form of scriptPath with administrator privileges
end run
APPLESCRIPT
