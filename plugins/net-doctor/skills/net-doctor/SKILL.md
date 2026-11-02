---
name: net-doctor
description: 诊断并修复中国大陆网络环境引发的依赖与仓库访问失败，覆盖 pip 安装超时、npm 下载缓慢、git clone GitHub 报错等场景。当用户反馈包装不上、下载中断、速度极慢，或出现 CONNECT tunnel failed、Read timed out、ECONNRESET 等网络错误，或需要为团队批量配置国内镜像加速时使用。内置多源并发测速、最优源自动回写、失败退避重试与一键回滚。
agent_created: true
---

# net-doctor

## 用途

把「网络问题导致的构建失败」从反复试错变成一次性的确定性修复。

核心判断：绝大多数 pip / npm / git 失败不是网络不通，而是**在用最慢、最不稳定的官方源直连**。本技能通过实测测速选出当前网络下最快的源，写回配置，并用重试层兜住偶发抖动。

## 何时使用

在以下情况触发本技能：

- pip / pip3 安装或下载超时：`Read timed out`、`ConnectionError`、`SSLError`
- npm / pnpm / yarn 安装卡住或失败：`ECONNRESET`、`ETIMEDOUT`、`network timeout`
- git clone / fetch / push GitHub 失败：`CONNECT tunnel failed`、`Failed to connect`、`RPC failed`
- 依赖安装「能跑但极慢」，明显不正常
- 用户明确要求「配置国内镜像」「加速下载」「一劳永逸解决网络问题」
- 为新机器 / 新团队做环境初始化

不要用于：真正的业务逻辑错误、认证失败（401/403）、仓库不存在的 404、本地磁盘问题。先确认错误确实发生在网络层。

## 调用方式（必须遵守）

**永远用绝对路径调用脚本，绝不要裸调 `net-doctor` / `net-retry`。**

原因：Agent 执行的 shell 通常是非交互式的，**不会加载 `~/.bashrc` / `~/.profile`**，PATH 里没有安装目录，alias 也不生效。裸命令会报 `command not found`，这不是本技能坏了，是调用方式错了。

统一写法（`<skill_dir>` 即本 SKILL.md 所在目录）：

```bash
# 体检（可改配置）
bash <skill_dir>/scripts/net-doctor
# 只体检不修改
bash <skill_dir>/scripts/net-doctor --dry-run
# 重试包装
bash <skill_dir>/scripts/net-retry npm install
# 一键还原
bash <skill_dir>/scripts/net-rollback
```

若 install.sh 已执行过，也可用其安装的绝对路径 `bash <skill_dir>/scripts/net-doctor` 等价调用。报 `command not found` 时，第一反应是改用绝对路径，而不是判定技能缺失。

## 工作流

### 第一步：判断是「没配」还是「配错了」

先读取现状，不要直接改配置：

```bash
pip config list 2>&1
npm config get registry 2>&1
git config --global --get-regexp '^url\.' 2>&1
```

若三项均为空或指向官方源，即为「没配」，直接进入第二步。

### 第二步：安装并执行体检

```bash
bash <skill_dir>/scripts/install.sh
```

安装器会：备份原配置 → 安装脚本到 `~/.net-doctor/bin` → 写入 shell PATH → git 传输加固 → 执行一次完整体检并自动选源。幂等，可重复执行。

只体检不修改：

```bash
bash <skill_dir>/scripts/install.sh --dry-run
```

### 第三步：读取体检结果并决策

体检输出三组（PyPI 镜像 / npm 镜像 / GitHub 通道）的实测延迟与「最优选择」。

判断规则：

- 官方源最快（常见于海外网络）：不要强行切镜像，直接说明「当前网络直连官方源最优，无需改动」
- 国内镜像最快：保留自动写入的结果即可
- GitHub 行显示「直连可用」：说明主站可达，无需加速改写
- 全部源不可用：先怀疑代理本身故障，再怀疑 DNS，最后怀疑物理断网

### 第四步：验证修复效果

不要只看配置写没写进去，要用真实动作验证：

```bash
pip download requests -d /tmp/nd_check --no-deps -q    # 目标: 10 秒内完成
npm view react version                                  # 目标: 2 秒内返回
git ls-remote --heads https://github.com/octocat/Hello-World.git
```

记录耗时，向用户报告「改之前 vs 改之后」的对比数据，而不是只说「已修复」。

### 第五步：日常使用

装依赖时套一层重试，避免偶发抖动被误判为失败：

```bash
bash <skill_dir>/scripts/net-retry npm install
bash <skill_dir>/scripts/net-retry pip install -r requirements.txt
```

出问题随时重新体检，无需人工判断换哪个源：

```bash
bash <skill_dir>/scripts/net-doctor
```

需要撤销全部改动：

```bash
bash <skill_dir>/scripts/net-rollback
```

## GitHub 阻断的特殊处理

若测速显示 `github.com` 直连不可达（curl 返回 000 或 git 报 `CONNECT tunnel failed, response 502`），说明主站链路被阻断，**重试与超时调整均无效**，必须走加速通道。

体检脚本会自动测速并选取可用的加速站，并且**只改写下载方向**：

- `insteadOf` 作用于 clone / fetch —— 公开仓库的这两步不携带任何凭据
- `pushInsteadOf` 把 push 强制回指 `https://github.com/`，git 中该规则优先级高于 `insteadOf`

因此**推送凭据永远不会发往第三方通道**。可这样验证：

```bash
git ls-remote --get-url                              # 显示加速地址（下载方向）
git remote get-url --push origin                     # 显示 github.com（推送方向）
```

注意事项：

- **私有仓库例外**。私有仓库的 clone / fetch 同样需要认证，此时凭据会经过加速通道。处理私有仓库或任何凭据敏感项目时，必须改用 `net-doctor --no-github`，该参数会清除全部改写
- 加速站会失效，不要硬编码某一个。始终让 net-doctor 重新测速决定
- 不要删除 `url.*` 配置后又假定 git 可用

## 关键约束

1. **绝不把代理地址写死到任何配置文件**。代理端口（如 `127.0.0.1:63300`）常由宿主程序动态注入、每次会话变化，写死会导致下次启动全盘断网。只在运行时读取环境变量。
2. **凭据不经第三方**。任何涉及认证的流量（push、私有仓库 clone）必须直连官方。默认配置已用 `pushInsteadOf` 保证 push 不走加速通道；私有仓库场景须显式 `--no-github`。
3. **环境变量优先级高于配置文件**。若已设置 `PIP_INDEX_URL` 或 `npm_config_registry`，改 ini / npmrc 不会生效，必须同步更新环境变量。net-doctor 已处理此点。
4. **不要不加诊断就换源**。海外用户切到国内镜像反而更慢，必须先测速。
5. **改动前必须备份**。install.sh 已自动备份到 `~/.net-doctor/backup/`。
6. **报告要给数据**。给出耗时对比，让用户能判断是否真的修好了。

## 平台差异（易错点）

pip 的配置文件名各平台不同，写错会导致「装完完全不生效」：

| 平台 | pip 配置文件 | 说明 |
|---|---|---|
| Linux | `~/.config/pip/pip.conf` | 注意是 .conf |
| macOS | `~/.config/pip/pip.conf` | 注意是 .conf |
| Windows | `%APPDATA%\pip\pip.ini` | 注意是 .ini |

npm 与 git 的配置路径三平台一致（`~/.npmrc`、`~/.gitconfig`）。

Alpine 等精简发行版默认无 bash，需先 `apk add bash curl gawk git`。

## 脚本清单

| 脚本 | 作用 |
|---|---|
| `scripts/install.sh` | 一键安装 + 首次体检，幂等 |
| `scripts/net-doctor` | 并发测速所有源，自动选最快并回写配置。支持 `--dry-run`（只看不改）、`--json`（机器可读）、`--no-github`（清除 GitHub 改写，私有仓库必用） |
| `scripts/net-retry` | 指数退避重试，全失败后自动触发体检 |
| `scripts/net-rollback` | 一键还原官方源 |

## 参考

- `references/mirrors.md` — 各镜像源地址、实测性能基线、选型依据
- `references/troubleshooting.md` — 常见报错与根因对照表
