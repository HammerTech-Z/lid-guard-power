#!/bin/bash
# 双击运行；会弹出系统管理员认证窗口
PKG_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$PKG_DIR/enable.sh"
if ! osascript <<EOF
do shell script "/bin/bash '"'"'"$SCRIPT"'"'"'" with administrator privileges
EOF
then
  echo "操作失败或被取消"
fi
