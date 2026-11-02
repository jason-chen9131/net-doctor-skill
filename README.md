# net-doctor

把「网络问题导致的构建失败」变成一次性的确定性修复。适用于中国大陆网络环境下 pip / npm / git 的下载超时、安装卡死、`git clone` 报 `CONNECT tunnel failed` 等场景。

本仓库同时是一个 **CodeBuddy / WorkBuddy 插件市场**，可直接被 CLI 和客户端读取。

## 它解决什么

大多数 pip / npm / git 失败不是因为网络不通，而是**在用最慢的官方源直连**。实测同一台机器、同一时段：

| 项目 | 修复前 | 修复后 |
|---|---|---|
| npm 包下载 | 46~53 KB/s | 360 KB/s |
| PyPI 索引 | 2~5 秒，频繁超时 | 0.24 秒 |
| pip 装 requests | 经常超时失败 | 2.3 秒 |
| npm 装 27 个包 | 分钟级，易中断 | 3.5 秒 |
| git clone GitHub | 100% 失败 | 3~5 秒成功 |

## 安装

### 方式一：作为插件市场安装（推荐）

```bash
codebuddy plugin marketplace add <本仓库地址>
codebuddy plugin install net-doctor@net-doctor-skills
```

支持三种源：

- git 仓库地址：`https://github.com/<user>/net-doctor-skill`
- zip 直链：`https://.../net-doctor-marketplace.zip`
- 本地目录：`/path/to/net-doctor-skill`

### 方式二：直接解压到 skills 目录

```bash
unzip net-doctor.zip -d ~/.workbuddy/skills/
bash ~/.workbuddy/skills/net-doctor/scripts/install.sh
```

### 方式三：只跑体检，不装

```bash
bash plugins/net-doctor/scripts/net-doctor --dry-run
```

## 安装后怎么用

装完不需要记命令，直接对 AI 说「我 npm 装不上了」即可，技能会自动触发。也可以手动：

```bash
net-doctor              # 测速 + 自动选最优源 + 回写配置
net-doctor --dry-run    # 只体检，不改任何配置
net-doctor --json       # 机器可读输出
net-retry <命令>        # 失败自动退避重试 3 次
net-rollback            # 一键还原官方源
```

## 安全边界

- **不写死代理地址**。代理端口常由宿主程序动态注入、每次会话变化，写死会导致下次启动全盘断网。
- **push 凭据不经过第三方**。GitHub 加速只作用于 clone / fetch（这两步不携带凭据），push 用 `pushInsteadOf` 强制回官方地址。
- **私有仓库必须先关加速**。私有仓库的 clone 本身需要认证，token 会经过加速站，执行 `net-doctor --no-github` 后再操作。
- **改动全部可逆**。安装前自动备份，`net-rollback` 一键还原。

## 兼容性

Windows（Git Bash / WSL）、macOS、Linux。已在 Debian 13、Alpine + gawk、macOS 分支（伪造 `uname`）、Windows Git Bash 实测。依赖 `bash 3.2+`、`curl`、`awk`，系统自带即可；`git` 仅用于 GitHub 加速部分。

## 仓库结构

```
.
├── .codebuddy-plugin/
│   └── marketplace.json          # 市场清单，声明 plugins[]
├── plugins/
│   └── net-doctor/
│       ├── .codebuddy-plugin/
│       │   └── plugin.json       # 插件清单
│       ├── SKILL.md              # 技能定义（触发条件 + 工作流）
│       ├── README.md
│       ├── scripts/              # install / net-doctor / net-retry / net-rollback
│       └── references/           # 镜像清单、故障处置手册
├── LICENSE
└── README.md
```

## 维护

镜像与加速站会失效。不要硬编码任何一个源，`net-doctor` 每次运行都会重新测速并改写配置。

## License

MIT
