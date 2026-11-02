#!/usr/bin/env bash
# net-retry — 网络类命令自动重试（指数退避）
#
# 用法:
#   net-retry npm install
#   net-retry pip install requests
#   NET_RETRY_MAX=5 net-retry git clone https://github.com/x/y
#
# 语义: 成功立即返回原状态码；失败按 1s/4s/10s 退避重试；
#       全部失败后自动触发 net-doctor 体检，最后返回原始退出码。

set -u

MAX="${NET_RETRY_MAX:-3}"
DELAYS="1 4 10 20 30"

if [ $# -eq 0 ]; then
  echo "用法: net-retry <命令> [参数...]"
  exit 2
fi

attempt=1
while :; do
  "$@"
  rc=$?
  [ $rc -eq 0 ] && exit 0
  [ $attempt -ge "$MAX" ] && break

  wait_s=$(echo "$DELAYS" | cut -d' ' -f"$attempt")
  [ -z "$wait_s" ] && wait_s=30
  echo "" >&2
  echo "[net-retry] 第 $attempt 次失败 (exit=$rc)，${wait_s}s 后重试 ($attempt/$MAX)..." >&2
  sleep "$wait_s"
  attempt=$((attempt+1))
done

echo "" >&2
echo "[net-retry] 已重试 $MAX 次仍失败，触发网络体检..." >&2

CANDIDATES="$(dirname "$0")/net-doctor.sh"
if [ -x "$CANDIDATES" ]; then
  "$CANDIDATES" --dry-run
elif [ -x "$(dirname "$0")/net-doctor" ]; then
  "$(dirname "$0")/net-doctor" --dry-run
elif command -v net-doctor >/dev/null 2>&1; then
  net-doctor --dry-run
fi
exit "$rc"
