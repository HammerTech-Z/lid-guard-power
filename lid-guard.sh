#!/bin/bash
# lid-guard v5.0-normal: AC + closed = awake and locked; battery + closed = sleep.
# Uses the existing immediate-password policy. No custom temperature-triggered sleep.
set -u
PATH=/usr/bin:/bin:/usr/sbin:/sbin
MODE_FILE=/usr/local/etc/lid-guard.mode
STATE=/usr/local/etc/lid-guard.state
LOG=/var/log/lid-guard.log
LOCK_RETRY=5
SLEEP_RETRY=30

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG" 2>/dev/null; }
read_mode() {
  mode=off
  if [ -r "$MODE_FILE" ]; then
    mode=$(tr -d '[:space:]' < "$MODE_FILE")
  fi
  case "$mode" in on|safe|off) : ;; *) mode=off ;; esac
}
read_power() {
  local raw
  raw=$(pmset -g ps 2>/dev/null) || { power=unknown; return; }
  case "$raw" in
    *"Now drawing from 'AC Power'"*) power=ac ;;
    *"Now drawing from 'Battery Power'"*) power=battery ;;
    *) power=unknown ;;
  esac
}
read_lid() {
  local raw
  lid=unknown
  raw=$(ioreg -n IOPMrootDomain -r -d 1 2>/dev/null) || return
  if printf '%s\n' "$raw" | grep -q '"AppleClamshellState" = Yes'; then lid=closed
  elif printf '%s\n' "$raw" | grep -q '"AppleClamshellState" = No'; then lid=open
  fi
}
read_disabled() {
  local raw
  disabled=unknown
  raw=$(pmset -g 2>/dev/null) || return
  if printf '%s\n' "$raw" | grep -qi 'SleepDisabled[[:space:]]*1'; then disabled=1
  elif printf '%s\n' "$raw" | grep -qi 'SleepDisabled[[:space:]]*0'; then disabled=0
  fi
}
ensure_disabled() {
  local want=$1
  read_disabled
  [ "$disabled" = "$want" ] && return 0
  if ! pmset -a disablesleep "$want" >/dev/null 2>&1; then
    log "WARN: setting disablesleep=$want failed"
    return 1
  fi
  read_disabled
  if [ "$disabled" != "$want" ]; then
    log "WARN: disablesleep=$want not yet confirmed (actual=$disabled)"
    return 1
  fi
  log "disablesleep=$disabled confirmed"
}
read_locked() {
  local raw
  locked=unknown
  raw=$(ioreg -n Root -d 1 2>/dev/null) || return
  if printf '%s\n' "$raw" | grep -q '"IOConsoleLocked" = Yes'; then locked=1
  elif printf '%s\n' "$raw" | grep -q '"IOConsoleLocked" = No'; then locked=0
  fi
}
request_display_lock() {
  # Refresh inputs immediately before the side effect.
  read_mode; read_power; read_lid
  [ "$mode" = on ] && [ "$power" = ac ] && [ "$lid" = closed ] || return 0
  if pmset displaysleepnow >/dev/null 2>&1; then
    read_locked
    if [ "$locked" = 1 ]; then log "display sleep requested; console lock VERIFIED"
    else log "WARN: display sleep requested; console lock unconfirmed (locked=$locked); will retry"
    fi
  else
    read_locked
    log "WARN: displaysleepnow failed (locked=$locked); will retry"
  fi
  last_lock=$(date +%s)
}
request_battery_sleep() {
  # Never use a cached lid or power reading to request whole-system sleep.
  read_mode
  case "$mode" in on|safe) : ;; *) return 0 ;; esac
  ensure_disabled 0 || return 0
  read_power; read_lid
  [ "$power" = battery ] && [ "$lid" = closed ] || return 0
  if pmset sleepnow >/dev/null 2>&1; then log "battery + closed: sleep requested"
  else log "WARN: battery sleep request failed; will retry"
  fi
  last_sleep=$(date +%s)
}
publish_state() {
  read_disabled; read_locked
  ac=unknown; [ "$power" = ac ] && ac=1; [ "$power" = battery ] && ac=0
  printf 'version=v5.0-normal mode=%s power=%s ac=%s lid=%s disabled=%s locked=%s fused=0 temp=n/a pid=%s %s\n' \
    "$mode" "$power" "$ac" "$lid" "$disabled" "$locked" "$$" "$(date '+%F %T')" \
    > "${STATE}.tmp.$$" && mv -f "${STATE}.tmp.$$" "$STATE"
}
cleanup() {
  trap - TERM INT HUP
  pmset -a disablesleep 0 >/dev/null 2>&1
  log "daemon exit: requested disablesleep=0"
  exit 0
}
trap cleanup TERM INT HUP
log "daemon start (pid $$) v5.0-normal"
last_lock=0
last_sleep=0
prev_power=unknown
prev_lid=unknown
prev_mode=unknown
prev_locked=unknown
while :; do
  read_mode; read_power; read_lid
  read_locked
  now=$(date +%s)
  if [ "$mode" = on ] && [ "$power" = ac ] && [ "$lid" != unknown ]; then
    ensure_disabled 1
    if [ "$lid" = closed ]; then
      if [ "$prev_lid" != closed ] || [ "$prev_power" != ac ] || [ "$prev_mode" != on ] || { [ "$locked" != 1 ] && [ $((now-last_lock)) -ge "$LOCK_RETRY" ]; }; then
        request_display_lock
      fi
    fi
  else
    ensure_disabled 0
    if [ "$mode" != off ] && [ "$power" = battery ] && [ "$lid" = closed ]; then
      if [ "$prev_lid" != closed ] || [ "$prev_power" != battery ] || [ "$prev_mode" = off ] || [ $((now-last_sleep)) -ge "$SLEEP_RETRY" ]; then
        request_battery_sleep
      fi
    fi
  fi
  publish_state
  if [ "$locked" = 1 ] && [ "$prev_locked" != 1 ]; then log "console lock VERIFIED"; fi
  prev_power=$power; prev_lid=$lid; prev_mode=$mode; prev_locked=$locked
  sleep 1
done
