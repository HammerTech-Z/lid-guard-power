#!/bin/bash
set -eu
PKG_DIR=$(cd "$(dirname "$0")" && pwd)
exec /usr/bin/osascript - "$PKG_DIR/enable.sh" <<'APPLESCRIPT'
on run argv
    set scriptPath to item 1 of argv
    do shell script "/bin/bash " & quoted form of scriptPath with administrator privileges
end run
APPLESCRIPT
