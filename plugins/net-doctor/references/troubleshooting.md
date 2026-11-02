# 报错对照与处置

按「看到的报错」定位根因，直接跳到对应处置方式。

## pip

### `Read timed out. (read timeout=15)`

根因：默认超时太短，叠加官方源慢。
处置：换国内镜像 + 提高超时。

```bash
pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple
pip config set global.timeout 60
pip config set global.retries 5
```

### `SSL: CERTIFICATE_VERIFY_FAILED`

根因：企业代理做了中间人解密，或系统根证书缺失。
处置：优先修复证书链；临时绕过用 `--trusted-host`（不推荐长期使用）。

```bash
pip install -i https://pypi.tuna.tsinghua.edu.cn/simple --trusted-host pypi.tuna.tsinghua.edu.cn <pkg>
```

### `ERROR: Could not find a version that satisfies the requirement`

根因：多为镜像同步延迟，新发布的包还没同步过来。
处置：临时回退官方源确认包是否存在，或等待同步。

### 版本与解释器不匹配

环境里同时存在多个 Python（如 3.12 与 3.13），`pip` 命令指向的与实际运行的不是同一个。
处置：用 `python -m pip` 代替 `pip`，确保同环境。

## npm

### `ECONNRESET` / `ETIMEDOUT` / `network timeout`

根因：官方 registry 在国内极慢（实测 46~53 KB/s），大依赖树必然超时。
处置：切 npmmirror，并提高重试参数。

```bash
npm config set registry https://registry.npmmirror.com
npm config set fetch-retries 5
npm config set fetch-timeout 120000
```

### 卡在 `postinstall` 或 `node-sass` / `sharp` / `canvas` 编译

根因：二进制文件从 GitHub Releases 拉取，被阻断。注意报错往往不在 registry 层，换 registry 无效。
处置：配置二进制镜像，见 `references/mirrors.md` 中的二进制包对照表。

### `ENOSPC` / `EMFILE`

根因：磁盘满或文件句柄不足，**不是网络问题**。
处置：清理磁盘 / 调整 `ulimit`，不要试图换源。

### `EEXIST` / `ENOTEMPTY` 删除 node_modules 失败

根因：Windows 文件占用或权限。
处置：关闭占用进程后重装，或使用 `rimraf node_modules`。

## git

### `CONNECT tunnel failed, response 502`

根因：代理层无法连接到 github.com。此时即使直连也已不通，属链路级阻断。
处置：确认 `curl -s -o /dev/null -w '%{http_code}' https://github.com` 是否返回 `000`。若是，改用加速通道；重试无意义。

### `Failed to connect to github.com port 443: Timed out`

根因：与上一条同类，主站 443 不可达。
处置：同上，走加速通道，或用 codeload 下载归档。

### `RPC failed; curl 56 GnuTLS recv error` / `early EOF` / `index-pack failed`

根因：大仓库传输中断，缓冲区不足或连接被重置。
处置：加大缓冲 + 浅克隆。

```bash
git config --global http.postBuffer 524288000
git config --global http.lowSpeedLimit 1000
git config --global http.lowSpeedTime 60
git clone --depth 1 <url>
```

### `warning: redirecting to https://<mirror>/https:/github.com/...`

根因：git 会规范化 URL 中的重复斜杠，加速通道再触发一次跳转。
处置：**属正常现象，功能不受影响**。若在意该提示，换用不会二次跳转的通道。

### `fatal: Authentication failed`

根因：凭据失效，**不是网络问题**。
处置：更新 token / 重新登录，不要试图换源。

## 通用

### 配置文件改了但不生效

根因：环境变量优先级高于配置文件。若存在 `PIP_INDEX_URL`、`npm_config_registry`，会覆盖 ini / npmrc。
处置：同步更新环境变量，或清除后只保留配置文件单一来源。

### 装完当时好用，重启后又慢

根因：只改了当前会话的环境变量，没持久化；或改的是临时配置。
处置：用 `pip config set` / `npm config set` 写用户级持久配置，不要用 `export`。

### 换了网络环境（出差 / 换运营商）后全部变慢

根因：原先选的镜像在当前网络下不再最优。
处置：重跑 `net-doctor` 重新测速选源，不要手工试。

## 判定顺序

遇到未知网络报错时按此顺序排除，避免误判：

1. `curl -s -o /dev/null -w '%{http_code}' <目标URL>` — 判是否真的不通
2. `nslookup <域名>` — 判 DNS 是否污染
3. `curl --resolve <域名>:443:<IP>` — 判是否 IP 层阻断
4. 检查代理环境变量 — 判是否代理故障
5. 最后才怀疑镜像配置
