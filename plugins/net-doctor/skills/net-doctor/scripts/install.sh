#!/usr/bin/env bash
# install.sh — net-doctor 一键安装器
#
# 用法:
#   ./install.sh                安装到 ~/.net-doctor/bin 并自动选源
#   ./install.sh --dry-run      只检查环境，不写入任何配置
#   ./install.sh --no-fix       只安装脚本，不改镜像配置
#   ./install.sh --dir <path>   自定义安装目录
#   ./install.sh --with-shell-integration
#                               可选：把安装目录写进 .bashrc/.zshrc 的 PATH
#                               （默认不改任何 shell 启动文件，收敛写入范围）
#
# 幂等: 可重复执行，不会重复写配置。

set -u

DRY=0
FIX=1
WITH_SHELL=0
DEST=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --no-fix)  FIX=0 ;;
    --with-shell-integration) WITH_SHELL=1 ;;
    --dir)     DEST="${2:-}"; shift ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
  esac
  shift
done

HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="${DEST:-$HOME/.net-doctor/bin}"
BACKUP_DIR="$HOME/.net-doctor/backup"
STAMP="$(date +%Y%m%d%H%M%S)"

echo ""
echo "=================================================="
echo "  net-doctor 安装器"
echo "=================================================="
echo ""

# ---------- 1. 环境检查 ----------
hard=""
for c in curl awk; do
  command -v "$c" >/dev/null 2>&1 || hard="$hard $c"
done
if [ -n "$hard" ]; then
  echo "✗ 缺少必需依赖:$hard"
  echo "  curl 用于测速、awk 用于解析结果，两者缺一不可。"
  echo "  安装方式:"
  echo "    Debian/Ubuntu : apt install -y curl gawk"
  echo "    Alpine        : apk add curl gawk"
  echo "    macOS         : 自带 curl / awk"
  echo "    Windows       : 使用 Git Bash 安装，自带全部依赖"
  exit 1
fi
# git 只影响 GitHub 加速这一段，缺了就降级而不是整体中止
if ! command -v git >/dev/null 2>&1; then
  echo "! 未安装 git：pip / npm 会正常配置，GitHub 加速这一部分会跳过"
  echo "  需要时安装: apt install -y git（macOS: brew install git）"
fi
echo "✓ 环境检查通过 ($(uname -s 2>/dev/null || echo unknown))"

# ---------- 2. 备份现有配置 ----------
if [ "$DRY" = "0" ]; then
  mkdir -p "$BACKUP_DIR"
  B="$BACKUP_DIR/original-$STAMP.txt"
  {
    echo "# net-doctor 安装前快照  $(date '+%Y-%m-%d %H:%M:%S')"
    echo "--- .npmrc ---"
    cat "$HOME/.npmrc" 2>/dev/null || echo "(不存在)"
    echo "--- git global ---"
    git config --global --list 2>/dev/null || echo "(空)"
    for f in "$HOME/.config/pip/pip.ini" "$HOME/.config/pip/pip.conf" \
             "${APPDATA:-$HOME/AppData/Roaming}/pip/pip.ini"; do
      [ -f "$f" ] && { echo "--- $f ---"; cat "$f"; }
    done
  } > "$B"
  echo "✓ 原配置已备份 → $B"
else
  echo "· dry-run：跳过备份"
fi

# ---------- 3. 安装脚本 ----------
if [ "$DRY" = "1" ]; then
  echo "· dry-run：将安装到 $DEST"
else
  mkdir -p "$DEST"
  for s in net-doctor net-retry net-rollback; do
    if [ -f "$HERE/$s.sh" ]; then
      cp -f "$HERE/$s.sh" "$DEST/$s"
      chmod +x "$DEST/$s"
    fi
  done
  echo "✓ 脚本已安装 → $DEST"
fi

# ---------- 4. 写入 shell 配置（PATH，可选） ----------
# 默认不改任何 shell 启动文件（安全评估建议：收敛写入范围）。
# 确实想要「新开终端直接敲 net-doctor」时，用 --with-shell-integration 显式开启；
# 写入前先备份 rc 文件，标记块幂等，可用 net-rollback 的思路手动删除标记块。
add_path_block() {
  local rc="$1" dest="$2"
  [ -f "$rc" ] || touch "$rc" 2>/dev/null || return
  if grep -q '>>> net-doctor >>>' "$rc" 2>/dev/null; then
    echo "· $rc 已配置，跳过"
    return
  fi
  cp -f "$rc" "$rc.net-doctor.bak.$STAMP" 2>/dev/null \
    && echo "· 已备份 $rc → $rc.net-doctor.bak.$STAMP"
  {
    echo ""
    echo "# >>> net-doctor >>>"
    echo "export PATH=\"$dest:\$PATH\""
    echo "# <<< net-doctor <<<"
  } >> "$rc"
  echo "✓ 已写入 $rc"
}

if [ "$DRY" = "0" ] && [ "$WITH_SHELL" = "1" ]; then
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ "$rc" = "$HOME/.zshrc" ] && [ ! -f "$rc" ]; then
      continue
    fi
    add_path_block "$rc" "$DEST"
  done
  # macOS/Linux 登录 shell 也读 profile
  if [ "$(uname -s 2>/dev/null)" != "MINGW64_NT" ] && [ "$(uname -s 2>/dev/null | cut -c1-6)" != "MINGW" ]; then
    add_path_block "$HOME/.bash_profile" "$DEST"
  fi
else
  echo "· 未修改 shell 启动文件（如需直接敲 net-doctor 命令，加 --with-shell-integration 重装，"
  echo "  或把 $DEST 加入 PATH）"
fi

# ---------- 5. git 传输加固（与镜像无关，纯稳定性） ----------
if [ "$DRY" = "0" ] && command -v git >/dev/null 2>&1; then
  git config --global http.postBuffer 524288000
  git config --global http.lowSpeedLimit 1000
  git config --global http.lowSpeedTime 60
  git config --global core.compression 0
  echo "✓ git 传输参数已加固（大仓库不再中断）"
fi

# ---------- 6. 自动选源 ----------
if [ "$DRY" = "1" ]; then
  echo ""
  echo "dry-run 结束，未做任何修改。"
  exit 0
fi

if [ "$FIX" = "1" ] && [ -x "$DEST/net-doctor" ]; then
  echo ""
  "$DEST/net-doctor"
else
  echo ""
  echo "已跳过自动选源（--no-fix）。"
  echo "随时可手动运行: $DEST/net-doctor"
fi

echo ""
echo "=================================================="
echo "  安装完成"
echo "=================================================="
echo "  体检 / 修复 : $DEST/net-doctor"
echo "  失败重试    : $DEST/net-retry <命令>"
echo "  一键还原    : $DEST/net-rollback（快照级完整还原，--list 查看快照）"
echo ""
echo "  不内置任何第三方 GitHub 代理（第三方代理可见下载内容、不校验完整性）。"
echo "  确需加速公开仓库时，指定你自己的可信代理:"
echo "    $DEST/net-doctor --github-accel https://your-proxy.example"
echo ""
echo "  测速带内容校验；配置修改前自动快照，修改后端到端验证，失败自动还原。"
echo ""
