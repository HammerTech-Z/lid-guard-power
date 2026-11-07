#!/bin/bash
set -eu
PKG_DIR=$(cd "$(dirname "$0")" && pwd)
exec /bin/bash "$PKG_DIR/install-for-agent.sh" --uninstall
