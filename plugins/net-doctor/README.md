# net-doctor

一劳永逸解决 pip / npm / git 因网络问题失败。

不是教你手改配置，而是：**测速 → 自动选最快的源 → 写回配置 → 失败自动重试**。

## 解决什么

| 现象 | 根因 | net-doctor 做什么 |
|---|---|---|
| `pip install` 卡住、超时 | 官方 PyPI 索引慢 | 自动切最快的国内镜像 |
| `npm install` 极慢、`ECONNRESET` | 官方 registry 仅约 50 KB/s | 切 npmmirror，7 倍提速 |
| `git clone` 报 `CONNECT tunnel failed` | github.com 链路被阻断 | 自动选可用加速通道改写 |
| 换网络后全部变慢 | 原镜像不再最优 | 重跑一次自动重新适配 |

## 安装

### AI 代理（WorkBuddy / CodeBuddy）

把 `net-doctor` 目录放进技能目录：

```bash
# 用户级（推荐，所有项目可用）
unzip net-doctor.zip -d ~/.workbuddy/skills/

# 或项目级
unzip net-doctor.zip -d <项目>/.workbuddy/skills/
```

之后直接说「我 npm 装不上」之类的话，技能会自动触发。

### 手动安装（不通过 AI）

解压后进入目录：

```bash
unzip net-doctor.zip
cd net-doctor

bash scripts/install.sh              # 一键安装 + 自动选源
bash scripts/install.sh --dry-run    # 只看体检结果，不改任何配置
bash scripts/install.sh --no-fix     # 只装脚本，镜像自己决定
```

Windows 用户请在 **Git Bash** 中执行（PowerShell 无法直接运行 .sh）。

## 安装后怎么用

```bash
net-doctor      # 体检 + 自动修复，任何时候网络不对劲就跑
net-retry npm install        # 命令失败自动重试 3 次
net-rollback    # 一键还原官方源，撤销所有改动
```

## 验证是否生效

```bash
pip download requests -d /tmp/t --no-deps -q    # 应在 10 秒内完成
npm view react version                          # 应在 2 秒内返回
git ls-remote --heads https://github.com/octocat/Hello-World.git
```

## 几个要点

- **不会写死代理地址**。代理端口通常由宿主程序动态注入、每次会话变化，写死会导致下次全盘断网。
- **凭据不经第三方**。GitHub 加速只作用于下载方向（clone / fetch），推送用 `pushInsteadOf` 强制回指官方，token 只会发往 github.com。可自行验证：

  ```bash
  git ls-remote --get-url            # 加速地址（下载）
  git remote get-url --push origin   # github.com（推送）
  ```

- **私有仓库请加 `--no-github`**。私有仓库的 clone 也需要认证，凭据会经过加速通道。处理这类仓库时先执行 `net-doctor --no-github` 清除改写。
- **海外网络不会被强行切镜像**。脚本会实测，官方源最快就保持官方源。
- **改动全部可逆**。安装前自动备份到 `~/.net-doctor/backup/`，随时 `net-rollback`。
- **加速站会失效**。不要关心用哪个，每次让 `net-doctor` 重新测速决定。

## 更多

- 镜像源清单、实测性能数据、二进制包镜像对照 → `references/mirrors.md`
- 各类报错的根因与处置 → `references/troubleshooting.md`
- 给 AI 的完整工作流 → `SKILL.md`

## 兼容性

Windows（Git Bash / WSL）、macOS、Linux 全部实测通过。

依赖 `bash`、`curl`、`awk`、`git`。多数系统自带，精简镜像需手动装：

```bash
apt install -y curl gawk git     # Debian / Ubuntu
apk add bash curl gawk git       # Alpine
```

注意 pip 配置文件在各平台的命名不同（Linux/macOS 是 `pip.conf`，Windows 是 `pip.ini`），脚本已自动处理。
