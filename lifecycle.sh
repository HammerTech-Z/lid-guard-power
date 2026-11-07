#!/bin/bash
# Shared installer helpers; daemon remains standalone. Compatible with macOS Bash 3.2.
set -eu
PATH=/usr/bin:/bin:/usr/sbin:/sbin
LABEL=co.user.lid-guard
ROOT=${LIDGUARD_ROOT:-}
REAL=1
[ -z "$ROOT" ] || REAL=0
if [ "$REAL" = 1 ]; then
  [ "$(uname -s)" = Darwin ] || { echo "仅支持 macOS" >&2; exit 1; }
  [ "$(id -u)" = 0 ] || { echo "需要管理员权限；请运行 bash install-for-agent.sh" >&2; exit 1; }
else
  case "$ROOT" in /*) ;; *) echo "LIDGUARD_ROOT 必须是绝对路径" >&2; exit 1 ;; esac
  [ "$ROOT" != / ] || { echo "测试根目录不能是 /" >&2; exit 1; }
fi
BIN="$ROOT/usr/local/bin/lid-guard.sh"
PLIST="$ROOT/Library/LaunchDaemons/$LABEL.plist"
ETC="$ROOT/usr/local/etc"
STATE="$ETC/lid-guard.state"
MODE="$ETC/lid-guard.mode"
LOG="$ROOT/var/log/lid-guard.log"
LOCK="$ROOT/var/run/lid-guard-install.lock"
FILES=("$BIN" "$PLIST" "$MODE" "$STATE")
loaded() { launchctl print "system/$LABEL" >/dev/null 2>&1; }
read_disabled() { pmset -g | awk '/SleepDisabled/{print $2;exit}'; }
preflight() {
  if [ "$REAL" = 1 ]; then
    ioreg -n IOPMrootDomain -r -d 1 | grep -q '"AppleClamshellState"' || {
      echo "未检测到 MacBook 合盖传感器；停止安装" >&2; return 1;
    }
    policy=$(sysadminctl -screenLock status 2>&1) || return 1
    case "$policy" in *"screenLock delay is immediate"*) ;; *)
      echo "需要先在系统设置中将关闭显示器后要求密码设为立即。当前：$policy" >&2; return 1 ;;
    esac
  fi
}
begin() {
  mkdir -p "$(dirname "$LOCK")"
  mkdir "$LOCK" 2>/dev/null || { echo "另一个安装/卸载正在运行，或存在残留锁：${LOCK}；停止操作" >&2; exit 1; }
  SNAP=$(mktemp -d "${TMPDIR:-/tmp}/lid-guard-transaction.XXXXXX") || { rmdir "$LOCK"; exit 1; }
  committed=0; started=0; was_loaded=0; old_disabled=0
  trap finish EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM HUP
  local i=0 f
  for f in "${FILES[@]}"; do
    if [ -e "$f" ] || [ -L "$f" ]; then cp -pP "$f" "$SNAP/$i"; fi
    i=$((i+1))
  done
  if [ "$REAL" = 1 ]; then
    loaded && was_loaded=1
    old_disabled=$(read_disabled)
    case "$old_disabled" in 0|1) ;; *) echo "无法读取 SleepDisabled，停止操作" >&2; return 1 ;; esac
  fi
  started=1
}
wait_unloaded() {
  local n
  for n in 1 2 3 4 5 6 7 8 9 10; do
    if ! loaded; then return 0; fi
    sleep 1
  done
  echo "服务未在 10 秒内完全卸载" >&2
  return 1
}
stop_service() {
  if [ "$REAL" = 1 ] && loaded; then
    launchctl bootout "system/$LABEL" || { echo "停止服务失败" >&2; return 1; }
    wait_unloaded
  fi
}
finish() {
  local rc=$? i=0 f rollback_failed=0
  trap - EXIT INT TERM HUP
  if [ "$committed" = 0 ] && [ "$started" = 1 ]; then
    echo "操作失败，正在恢复操作前状态……" >&2
    if [ "$REAL" = 1 ] && loaded; then
      launchctl bootout "system/$LABEL" || rollback_failed=1
      wait_unloaded || rollback_failed=1
    fi
    for f in "${FILES[@]}"; do
      if [ -e "$SNAP/$i" ] || [ -L "$SNAP/$i" ]; then
        rm -f "$f" && cp -pP "$SNAP/$i" "$f" || rollback_failed=1
      else
        rm -f "$f" || rollback_failed=1
      fi
      i=$((i+1))
    done
    if [ "$REAL" = 1 ]; then
      if [ "$was_loaded" = 1 ]; then
        if loaded; then rollback_failed=1
        else launchctl bootstrap system "$PLIST" || rollback_failed=1; fi
      fi
      pmset -a disablesleep "$old_disabled" || rollback_failed=1
    fi
    if [ "$rollback_failed" = 0 ]; then echo "已恢复操作前文件与服务配置" >&2
    else echo "自动恢复未全部成功，备份保留在 ${SNAP}，请人工检查" >&2; fi
    [ "$rc" != 0 ] || rc=1
  fi
  if [ "$rollback_failed" = 0 ]; then rm -rf "$SNAP"; fi
  rmdir "$LOCK" || true
  exit "$rc"
}
