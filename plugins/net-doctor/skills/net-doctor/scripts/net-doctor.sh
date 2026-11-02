#!/usr/bin/env bash
# net-doctor — 网络体检 + 自动选最快镜像源并回写配置
#
# 用法:
#   net-doctor             体检并修复（pip/npm 自动选源；GitHub 仅检测，默认不改写）
#   net-doctor --dry-run   只体检不修改
#   net-doctor --github-accel  显式允许公开仓库下载走第三方代理（有供应链风险，私有仓库禁用）
#   net-doctor --no-github 兼容旧参数：清除 GitHub 改写（等同默认行为）
#   net-doctor --json      输出机器可读结果（便于被脚本消费）
#
# 跨平台: Windows(Git Bash/WSL) / macOS / Linux
# 依赖: bash 3.2+, curl, awk（系统自带）

set -u

DRY=0
JSON=0
NO_GH=0
GH_ACCEL=0
for a in "$@"; do
  case "$a" in
    --dry-run)        DRY=1 ;;
    --json)           JSON=1 ;;
    --no-github)      NO_GH=1 ;;
    --github-accel|--github-proxy) GH_ACCEL=1 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
  esac
done

# ---------- 平台适配 ----------
# pip 配置文件名各平台不同，写错会导致「装了但完全不生效」：
#   Linux / macOS 读 ~/.config/pip/pip.conf
#   Windows      读 %APPDATA%\pip\pip.ini
OS="$(uname -s 2>/dev/null || echo unknown)"
case "$OS" in
  Darwin|Linux)
    PIP_DIR="$HOME/.config/pip"; PIP_INI="$PIP_DIR/pip.conf" ;;
  *)
    PIP_DIR="${APPDATA:-$HOME/AppData/Roaming}/pip"; PIP_INI="$PIP_DIR/pip.ini" ;;
esac
NPMRC="$HOME/.npmrc"

TMPD="$HOME/.net-doctor/tmp.$$"
mkdir -p "$TMPD" 2>/dev/null || TMPD="${TMPDIR:-/tmp}/netdoc.$$"
mkdir -p "$TMPD" 2>/dev/null
cleanup() { rm -f "$TMPD"/* 2>/dev/null; rmdir "$TMPD" 2>/dev/null; }
trap 'cleanup' EXIT

# ---------- 候选源 ----------
PIP_C=(
  "tuna|清华|https://pypi.tuna.tsinghua.edu.cn/simple"
  "ustc|中科大|https://mirrors.ustc.edu.cn/pypi/simple"
  "tencent|腾讯云|https://mirrors.cloud.tencent.com/pypi/simple"
  "aliyun|阿里云|https://mirrors.aliyun.com/pypi/simple"
  "pypi|官方|https://pypi.org/simple"
)
NPM_C=(
  "npmmirror|npmmirror|https://registry.npmmirror.com"
  "tencent|腾讯云|https://mirrors.cloud.tencent.com/npm/"
  "npmjs|官方|https://registry.npmjs.org"
)
GH_C=(
  "ghfast|ghfast.top|https://ghfast.top"
  "ghproxy|gh-proxy.com|https://gh-proxy.com"
  "ghproxyhkor|hk.gh-proxy.org|https://hk.gh-proxy.org"
  "direct|直连|"
)

# 探测必须打真实的 git 协议端点，不能用首页或 codeload 的 zip：
# 实测首页可能返回 200 但拖满超时，codeload 在 github.com 443 被阻断时仍然可用，
# 用它探测会把「clone 必然失败」误判成「直连可用」。
GH_PROBE_GIT="/octocat/Hello-World.git/info/refs?service=git-upload-pack"
GH_TEST="/https://github.com${GH_PROBE_GIT}"

# ---------- 测速 ----------
probe() {  # probe <url> [timeout] -> 秒；失败 99
  local url="$1" tmo="${2:-8}" best=99 t
  [ -z "$url" ] && { echo 99; return; }
  for _ in 1 2; do
    t=$(curl -sL -o /dev/null -w '%{time_total}' --max-time "$tmo" "$url" 2>/dev/null) || t=99
    [ -z "$t" ] && t=99
    awk -v a="$t" -v b="$best" 'BEGIN{exit !(a<b)}' && best="$t"
  done
  echo "$best"
}

run_group() {  # run_group <标签> <超时> <candidates...>
  local label="$1" tmo="$2"; shift 2
  local -a arr=("$@")
  local i=0 entry url
  for entry in "${arr[@]}"; do
    url="${entry##*|}"
    ( probe "$url" "$tmo" > "$TMPD/$label.$i" ) &
    i=$((i+1))
  done
  wait
  i=0
  for entry in "${arr[@]}"; do
    url="${entry##*|}"
    printf "%s|%s|%s|%s\n" "$label" "${entry%%|*}" "$url" \
      "$(cat "$TMPD/$label.$i" 2>/dev/null || echo 99)" >> "$TMPD/results"
    i=$((i+1))
  done
}

run_group_gh() {
  local i=0 entry base
  for entry in "${GH_C[@]}"; do
    base="${entry#*|}"; base="${base#*|}"
    if [ -z "$base" ]; then
      ( probe "https://github.com${GH_PROBE_GIT}" 10 > "$TMPD/gh.$i" ) &
    else
      ( probe "${base}${GH_TEST}" 10 > "$TMPD/gh.$i" ) &
    fi
    i=$((i+1))
  done
  wait
  i=0
  for entry in "${GH_C[@]}"; do
    base="${entry#*|}"; base="${base#*|}"
    printf "gh|%s|%s|%s\n" "${entry%%|*}" "$base" \
      "$(cat "$TMPD/gh.$i" 2>/dev/null || echo 99)" >> "$TMPD/results"
    i=$((i+1))
  done
}

# 先确认工具链，避免把「缺工具」误报成「网络不通」
if ! command -v curl >/dev/null 2>&1; then
  echo "✗ 缺少 curl，无法测速（这不是网络问题）。"
  echo "  Debian/Ubuntu: apt install -y curl | Alpine: apk add curl | macOS: 自带"
  exit 2
fi
if ! command -v awk >/dev/null 2>&1; then
  echo "✗ 缺少 awk，无法解析测速结果。"
  echo "  Debian/Ubuntu: apt install -y gawk | Alpine: apk add gawk"
  exit 2
fi

echo ""
echo "=================================================="
echo "  net-doctor  网络体检  $(date '+%Y-%m-%d %H:%M:%S')"
echo "=================================================="
if [ -n "${HTTPS_PROXY:-}${https_proxy:-}" ]; then
  echo "代理: ${HTTPS_PROXY:-$https_proxy}"
else
  echo "代理: 未启用（直连）"
fi
echo ""
echo "正在并发测速（每源取样 2 次）..."
: > "$TMPD/results"
run_group pip 8 "${PIP_C[@]}"
run_group npm 8 "${NPM_C[@]}"
run_group_gh
echo ""

label_of() {
  case "$1" in
    tuna) echo 清华 ;; ustc) echo 中科大 ;; tencent) echo 腾讯云 ;;
    aliyun) echo 阿里云 ;; pypi) echo "PyPI官方" ;; npmmirror) echo npmmirror ;;
    npmjs) echo "npm官方" ;; ghfast) echo ghfast.top ;;
    ghproxy) echo gh-proxy.com ;; ghproxyhkor) echo hk.gh-proxy.org ;;
    direct) echo "GitHub直连" ;; *) echo "$1" ;;
  esac
}

fmt_t() { awk -v t="$1" 'BEGIN{ if (t>=99) printf "--"; else printf "%.2fs", t }'; }

show_group() {
  echo "$2"
  grep "^$1|" "$TMPD/results" 2>/dev/null | while IFS='|' read -r _ id url t; do
    if awk -v x="$t" 'BEGIN{exit !(x<99)}'; then
      printf "  %-16s %-8s %s\n" "$(label_of "$id")" "$(fmt_t "$t")" "$url"
    else
      printf "  %-16s %-8s %s\n" "$(label_of "$id")" "不可用" "$url"
    fi
  done
  echo ""
}

show_group pip "【PyPI 镜像】"
show_group npm "【npm 镜像】"
show_group gh  "【GitHub 通道】"

pick() {  # 输出 "time|url"
  grep "^$1|" "$TMPD/results" 2>/dev/null | awk -F'|' '$4 < 99 {print $4"|"$3}' | sort -n | head -1
}
pick2() {
  grep "^$1|" "$TMPD/results" 2>/dev/null | awk -F'|' '$4 < 99 {print $4"|"$3}' | sort -n | sed -n '2p'
}

PIP_B="$(pick pip)";  PIP_URL="${PIP_B#*|}"
PIP_A="$(pick2 pip)"; PIP_ALT="${PIP_A#*|}"
NPM_B="$(pick npm)";  NPM_URL="${NPM_B#*|}"
GH_B="$(pick gh)";    GH_URL="${GH_B#*|}"

if [ "$JSON" = "1" ]; then
  # github 为空表示直连最优；github_direct 让调用方不必猜。
  # github_accel=false 表示本次不会写入任何第三方改写（安全默认值）。
  if [ -z "$GH_URL" ]; then GH_DIRECT=true; else GH_DIRECT=false; fi
  if [ "$GH_ACCEL" = "1" ] && [ "$NO_GH" != "1" ] && [ -n "$GH_URL" ]; then GH_ON=true; else GH_ON=false; fi
  printf '{"pip":"%s","pip_alt":"%s","npm":"%s","github":"%s","github_direct":%s,"github_accel":%s}\n' \
    "$PIP_URL" "$PIP_ALT" "$NPM_URL" "$GH_URL" "$GH_DIRECT" "$GH_ON"
  exit 0
fi

if [ -z "$PIP_URL" ] && [ -z "$NPM_URL" ]; then
  echo "✗ 所有源均不可达。"
  [ -n "${HTTPS_PROXY:-}${https_proxy:-}" ] && echo "  当前有代理，很可能是代理本身故障。"
  echo "  请检查本机网络 / DNS 后重试。"
  exit 1
fi

echo "=================================================="
echo "  最优选择"
echo "=================================================="
[ -n "$PIP_URL" ] && echo "  PyPI   : $PIP_URL  (备选: ${PIP_ALT:-无})"
[ -n "$NPM_URL" ] && echo "  npm    : $NPM_URL"
if [ -n "$GH_URL" ]; then
  if [ "$GH_ACCEL" = "1" ] && [ "$NO_GH" != "1" ]; then
    echo "  GitHub : 直连不可达 → 将按 --github-accel 启用 $GH_URL（有供应链风险）"
  else
    echo "  GitHub : 直连不可达 → $GH_URL 可用，但加速默认关闭（需 --github-accel）"
  fi
else
  echo "  GitHub : 直连可用，无需加速"
fi
echo ""

[ "$DRY" = "1" ] && { echo "--dry-run：未修改任何配置。"; exit 0; }

# ---------- 跨平台写配置（不依赖 sed -i） ----------
replace_line() {  # <file> <prefix> <newline>；成功返回 0，失败返回 1
  local f="$1" prefix="$2" nl="$3" found=0 line tmp
  tmp="$f.nettmp"
  : > "$tmp" 2>/dev/null || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "$prefix"*)
        if [ "$found" -eq 0 ]; then printf '%s\n' "$nl" >> "$tmp"; found=1; fi ;;
      *) printf '%s\n' "$line" >> "$tmp" ;;
    esac
  done < "$f"
  [ "$found" -eq 0 ] && printf '%s\n' "$nl" >> "$tmp"
  # 用 cat 覆写而非 mv：Windows 下目标文件常被进程占用，mv 覆盖会 Permission denied
  if cat "$tmp" > "$f" 2>/dev/null; then
    rm -f "$tmp" 2>/dev/null
    return 0
  fi
  rm -f "$tmp" 2>/dev/null
  return 1
}

apply_pip() {
  local url="$1" alt="$2"
  mkdir -p "$(dirname "$PIP_INI")" 2>/dev/null
  if [ ! -f "$PIP_INI" ]; then
    if {
      echo "[global]"
      echo "index-url = $url"
      [ -n "$alt" ] && echo "extra-index-url = $alt"
      echo "timeout = 60"
      echo "retries = 5"
      echo "disable-pip-version-check = true"
    } > "$PIP_INI" 2>/dev/null; then
      echo "  ✓ pip 配置已创建 → $url"
    else
      echo "  ✗ pip 配置写入失败：$PIP_INI（检查目录权限）"
    fi
  else
    if replace_line "$PIP_INI" "index-url" "index-url = $url"; then
      if [ -n "$alt" ]; then
        if grep -q '^extra-index-url' "$PIP_INI"; then
          replace_line "$PIP_INI" "extra-index-url" "extra-index-url = $alt"
        else
          printf 'extra-index-url = %s\n' "$alt" >> "$PIP_INI"
        fi
      fi
      echo "  ✓ pip 配置已更新 → $url"
    else
      echo "  ✗ pip 配置写入失败：$PIP_INI（文件被占用或无权限）"
    fi
  fi
}

apply_npm() {
  local url="$1"
  if [ ! -f "$NPMRC" ]; then
    if printf 'registry=%s\nfetch-timeout=120000\nfetch-retries=5\n' "$url" > "$NPMRC" 2>/dev/null; then
      echo "  ✓ npm 配置已创建 → $url"
    else
      echo "  ✗ npm 配置写入失败：$NPMRC"
    fi
  else
    if replace_line "$NPMRC" "registry=" "registry=$url"; then
      echo "  ✓ npm 配置已更新 → $url"
    else
      echo "  ✗ npm 配置写入失败：$NPMRC（被 npm 进程占用？关闭后重试）"
    fi
  fi
}

apply_git() {
  local base="$1"
  if ! command -v git >/dev/null 2>&1; then
    echo "  · 未安装 git，跳过 GitHub 相关配置（pip / npm 不受影响）"
    return
  fi
  # 先清掉所有旧改写规则（含 pushInsteadOf），避免规则叠加打架
  git config --global --get-regexp '^url\..*\.(insteadof|pushinsteadof)$' 2>/dev/null | while read -r key _v; do
    git config --global --unset "$key" 2>/dev/null
  done
  if [ -z "$base" ]; then
    echo "  · 已清除所有 GitHub 第三方改写（当前不使用任何代理通道）"
    return
  fi
  # 只有显式 --github-accel 才会走到这里。
  # 风险必须写在配置写入之前，而不是写在文档里等人去翻。
  echo "  ! 已按 --github-accel 启用第三方代理：$base"
  echo "    · 该代理可见全部下载内容，且 git 无法校验制品完整性（可下发被篡改的提交历史）"
  echo "    · 私有仓库 / 需要凭据的 clone 严禁使用：代理可回 401 诱导 git 交出账号口令或 PAT"
  echo "    · 核验下载结果：git log -1 --format=%H 与官方发布记录 / 签名比对"
  # 只改写下载方向
  git config --global "url.${base}/https://github.com/.insteadOf" "https://github.com/" 2>/dev/null
  # push 强制回官方：pushInsteadOf 优先级高于 insteadOf，
  # 保证推送时的账号凭据只会发往 github.com，绝不经过第三方通道
  if git config --global "url.https://github.com/.pushInsteadOf" "https://github.com/" 2>/dev/null; then
    echo "  ✓ git 下载走 ${base}（push 仍直连官方）"
  else
    echo "  ✗ git 配置写入失败，请检查 git 是否可用"
  fi
}

[ -n "$PIP_URL" ] && apply_pip "$PIP_URL" "$PIP_ALT"
[ -n "$NPM_URL" ] && apply_npm "$NPM_URL"
if [ "$NO_GH" = "1" ]; then
  apply_git ""
  echo "  · 已清除 GitHub 第三方改写（--no-github）"
elif [ "$GH_ACCEL" = "1" ]; then
  apply_git "$GH_URL"
else
  # 默认安全：永不把 GitHub 流量导向第三方。
  # 老版本写入的 insteadOf 规则也会在这里被清除，属于顺带修复。
  apply_git ""
  if [ -n "$GH_URL" ]; then
    echo "  ! GitHub 直连不可达，加速默认关闭（第三方代理可见下载内容、无法校验完整性）"
    echo "    需要时显式开启：net-doctor --github-accel   仅限公开仓库，私有仓库禁用"
  fi
fi
# 环境变量优先级高于配置文件，必须同步，否则改了等于没改
if command -v setx >/dev/null 2>&1; then
  [ -n "$PIP_URL" ] && setx PIP_INDEX_URL "$PIP_URL" >/dev/null 2>&1
  [ -n "$NPM_URL" ] && setx npm_config_registry "$NPM_URL" >/dev/null 2>&1
  echo "  ✓ 用户级环境变量已同步"
fi

echo ""
echo "完成。新开的终端 / 新会话生效。"
