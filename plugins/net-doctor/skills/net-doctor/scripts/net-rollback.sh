#!/usr/bin/env bash
# net-rollback — 还原到官方源（撤销所有镜像配置）

set -u

OS="$(uname -s 2>/dev/null || echo unknown)"
case "$OS" in
  Darwin|Linux) PIP_INI="$HOME/.config/pip/pip.conf" ;;
  *)            PIP_INI="${APPDATA:-$HOME/AppData/Roaming}/pip/pip.ini" ;;
esac
NPMRC="$HOME/.npmrc"

echo "正在回滚网络配置..."
echo ""

if [ -f "$PIP_INI" ]; then
  mv -f "$PIP_INI" "$HOME/pip.ini.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null \
    && echo "  ✓ 已移走 pip 配置（恢复官方 PyPI）"
fi

if [ -f "$NPMRC" ]; then
  mv -f "$NPMRC" "$HOME/.npmrc.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null \
    && echo "  ✓ 已移走 .npmrc（恢复官方 npm）"
fi

# 清除 GitHub 加速改写（含 pushInsteadOf）
git config --global --get-regexp '^url\..*\.(insteadof|pushinsteadof)$' 2>/dev/null | while read -r key _v; do
  git config --global --unset "$key" 2>/dev/null
done
echo "  ✓ 已清除 GitHub 加速改写"

# Windows 用户级环境变量
if command -v reg >/dev/null 2>&1; then
  for v in PIP_INDEX_URL PIP_EXTRA_INDEX_URL PIP_TIMEOUT PIP_RETRIES \
           PIP_DISABLE_PIP_VERSION_CHECK npm_config_registry \
           npm_config_fetch_timeout npm_config_fetch_retries \
           ELECTRON_MIRROR SASS_BINARY_SITE PUPPETEER_DOWNLOAD_BASE_URL \
           PLAYWRIGHT_DOWNLOAD_HOST; do
    reg delete "HKCU\Environment" /v "$v" /f >/dev/null 2>&1
  done
  echo "  ✓ 已清除镜像相关环境变量"
fi

echo ""
echo "完成。git 的 http.* 稳定性参数保留（无副作用）。"
