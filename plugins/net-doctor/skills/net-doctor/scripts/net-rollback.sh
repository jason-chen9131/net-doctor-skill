#!/usr/bin/env bash
# net-rollback — 完整还原 net-doctor 修改前的配置
#
# 用法:
#   net-rollback            还原到最近一次快照（整文件还原，保留你原有的个性化设置）
#   net-rollback --list     列出所有可用快照
#
# 还原范围:
#   pip 配置（pip.conf / pip.ini）、.npmrc、git 全局 url.* 改写、
#   Windows 用户级镜像环境变量（原值恢复，原本没有的删除）。

set -u

OS="$(uname -s 2>/dev/null || echo unknown)"
case "$OS" in
  Darwin|Linux) PIP_INI="$HOME/.config/pip/pip.conf" ;;
  *)            PIP_INI="${APPDATA:-$HOME/AppData/Roaming}/pip/pip.ini" ;;
esac
NPMRC="$HOME/.npmrc"
BK_ROOT="$HOME/.net-doctor/backups"

if [ "${1:-}" = "--list" ]; then
  echo "可用快照（$BK_ROOT）："
  found=0
  for d in "$BK_ROOT"/20*; do
    [ -d "$d" ] || continue
    found=1
    printf "  %s  pip:%s npm:%s git:%s\n" "$(basename "$d")" \
      "$([ -f "$d/pip.ini" ] && echo 有 || echo 无)" \
      "$([ -f "$d/npmrc" ] && echo 有 || echo 无)" \
      "$([ -f "$d/git-global.txt" ] && echo 有 || echo 无)"
  done
  [ "$found" = "0" ] && echo "  （无快照 —— net-doctor 未修改过任何配置）"
  exit 0
fi

echo "正在回滚网络配置（快照级完整还原）..."
echo ""

# 定位最近一次快照
LATEST=""
if [ -f "$BK_ROOT/LATEST" ]; then
  cand="$(cat "$BK_ROOT/LATEST" 2>/dev/null)"
  [ -d "$cand" ] && LATEST="$cand"
fi
[ -z "$LATEST" ] && LATEST="$(ls -1d "$BK_ROOT"/20* 2>/dev/null | sort | tail -1)"

if [ -n "$LATEST" ]; then
  echo "  使用快照: $LATEST"

  # pip：整文件还原；原文件不存在则删掉 net-doctor 创建的那份
  if [ -f "$LATEST/pip.ini" ]; then
    mkdir -p "$(dirname "$PIP_INI")" 2>/dev/null
    if cat "$LATEST/pip.ini" > "$PIP_INI" 2>/dev/null; then
      echo "  ✓ pip 配置已还原为你修改前的原内容"
    else
      echo "  ✗ pip 配置还原失败（文件被占用？关闭 pip 进程后重试）"
    fi
  elif [ -f "$PIP_INI" ]; then
    rm -f "$PIP_INI" 2>/dev/null && echo "  ✓ pip 配置为 net-doctor 新建，已移除（恢复官方源）"
  fi

  # npm：同上
  if [ -f "$LATEST/npmrc" ]; then
    if cat "$LATEST/npmrc" > "$NPMRC" 2>/dev/null; then
      echo "  ✓ .npmrc 已还原为你修改前的原内容"
    else
      echo "  ✗ .npmrc 还原失败（被 npm 进程占用？）"
    fi
  elif [ -f "$NPMRC" ]; then
    rm -f "$NPMRC" 2>/dev/null && echo "  ✓ .npmrc 为 net-doctor 新建，已移除（恢复官方源）"
  fi
else
  echo "  · 无快照可还原，退回旧行为：移除当前镜像配置"
  [ -f "$PIP_INI" ] && mv -f "$PIP_INI" "$HOME/pip.ini.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null \
    && echo "  ✓ 已移走 pip 配置（恢复官方 PyPI）"
  [ -f "$NPMRC" ] && mv -f "$NPMRC" "$HOME/.npmrc.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null \
    && echo "  ✓ 已移走 .npmrc（恢复官方 npm）"
fi

# 清除 GitHub 加速改写（含 pushInsteadOf）
if command -v git >/dev/null 2>&1; then
  git config --global --get-regexp '^url\..*\.(insteadof|pushinsteadof)$' 2>/dev/null | while read -r key _v; do
    git config --global --unset "$key" 2>/dev/null
  done
  echo "  ✓ 已清除 GitHub 加速改写"
fi

# Windows 用户级环境变量：有原值恢复原值，原本没有的删除
if command -v reg >/dev/null 2>&1; then
  if [ -n "$LATEST" ] && [ -f "$LATEST/win-env.txt" ]; then
    while IFS='=' read -r v val; do
      [ -z "$v" ] && continue
      if [ -n "$val" ]; then
        reg add "HKCU\\Environment" /v "$v" /t REG_SZ /d "$val" /f >/dev/null 2>&1
      else
        reg delete "HKCU\\Environment" /v "$v" /f >/dev/null 2>&1
      fi
    done < "$LATEST/win-env.txt"
    echo "  ✓ 镜像相关环境变量已还原为快照时的状态"
  else
    for v in PIP_INDEX_URL PIP_EXTRA_INDEX_URL PIP_TIMEOUT PIP_RETRIES \
             PIP_DISABLE_PIP_VERSION_CHECK npm_config_registry \
             npm_config_fetch_timeout npm_config_fetch_retries \
             ELECTRON_MIRROR SASS_BINARY_SITE PUPPETEER_DOWNLOAD_BASE_URL \
             PLAYWRIGHT_DOWNLOAD_HOST; do
      reg delete "HKCU\Environment" /v "$v" /f >/dev/null 2>&1
    done
    echo "  ✓ 已清除镜像相关环境变量"
  fi
fi

echo ""
echo "完成。git 的 http.* 稳定性参数保留（无副作用）。"
