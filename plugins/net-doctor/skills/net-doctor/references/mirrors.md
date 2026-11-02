# 镜像源清单与选型依据

## 实测性能基线

以下数据在一台中国大陆家宽（电信）环境实测，供选型参考。不同地区、运营商、时段会有差异，**实际使用必须现场测速，不要照搬**。

| 源 | 索引延迟 | 包下载速度 | 结论 |
|---|---|---|---|
| pypi.org（官方） | 2.0~5.2 s，频繁超 12 s | 不稳定 | 仅海外推荐 |
| pypi.tuna.tsinghua.edu.cn | 0.17~0.25 s | 快 | 国内首选 |
| mirrors.ustc.edu.cn | 0.18~0.24 s | 快 | 国内备选 |
| mirrors.cloud.tencent.com | 0.25~0.40 s | 快 | 国内备选 |
| mirrors.aliyun.com | 经常不可达 | — | 不推荐做默认 |
| registry.npmjs.org（官方） | 0.7~1.1 s | 46~53 KB/s | 国内不可用 |
| registry.npmmirror.com | 0.13~0.17 s | 360 KB/s | 国内首选 |

结论：国内环境下 npm 官方源是最大的失败源，单包速度差 7 倍以上，大依赖树必然超时。

## PyPI 镜像

| 名称 | URL |
|---|---|
| 清华 TUNA | `https://pypi.tuna.tsinghua.edu.cn/simple` |
| 中科大 USTC | `https://mirrors.ustc.edu.cn/pypi/simple` |
| 腾讯云 | `https://mirrors.cloud.tencent.com/pypi/simple` |
| 阿里云 | `https://mirrors.aliyun.com/pypi/simple` |
| 官方 | `https://pypi.org/simple` |

配置方式（跨平台首选）：

```bash
pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple
pip config set global.extra-index-url https://mirrors.ustc.edu.cn/pypi/simple
pip config set global.timeout 60
pip config set global.retries 5
```

配置文件位置：
- Windows：`%APPDATA%\pip\pip.ini`
- macOS / Linux：`~/.config/pip/pip.conf`（旧版本兼容 `pip.ini`）

## npm 镜像

| 名称 | URL |
|---|---|
| npmmirror（淘宝） | `https://registry.npmmirror.com` |
| 腾讯云 | `https://mirrors.cloud.tencent.com/npm/` |
| 官方 | `https://registry.npmjs.org` |

### 二进制包镜像（关键）

npm 安装失败有很大一部分不在 registry，而在 `postinstall` 阶段下载的二进制文件。这些文件默认从 GitHub Releases 或厂商 CDN 拉取，国内极易超时。必须一并指向镜像。

| 变量 / 配置项 | 镜像地址 |
|---|---|
| `sass_binary_site` | `https://registry.npmmirror.com/-/binary/node-sass` |
| `sharp_binary_host` | `https://registry.npmmirror.com/-/binary/sharp` |
| `sharp_libvips_binary_host` | `https://registry.npmmirror.com/-/binary/sharp-libvips` |
| `node_sqlite3_binary_host_mirror` | `https://registry.npmmirror.com/-/binary/sqlite3` |
| `canvas_binary_host_mirror` | `https://registry.npmmirror.com/-/binary/canvas` |
| `chromedriver_cdnurl` | `https://registry.npmmirror.com/-/binary/chromedriver` |
| `electron_mirror` | `https://registry.npmmirror.com/-/binary/electron/` |
| `electron_builder_binaries_mirror` | `https://registry.npmmirror.com/-/binary/electron-builder-binaries/` |
| `puppeteer_download_base_url` | `https://registry.npmmirror.com/-/binary/chrome-for-testing` |
| `playwright_download_host` | `https://registry.npmmirror.com/-/binary/playwright` |

写入 `~/.npmrc` 即可全局生效。

### 发布注意

切到镜像后 `npm publish` 会默认发往镜像站，必然失败。发布时必须显式指定官方源：

```bash
npm publish --registry=https://registry.npmjs.org
```

## GitHub 加速通道

当 `github.com` 主站 443 被阻断时（表现为所有官方 IP 超时，curl 返回 `000`，git 报 `CONNECT tunnel failed, response 502`），仅调整超时与重试无效，必须改写地址。

可用通道（会失效，需现场测速）：

| 通道 | 地址 |
|---|---|
| ghfast | `https://ghfast.top` |
| gh-proxy | `https://gh-proxy.com` |
| hk.gh-proxy.org | `https://hk.gh-proxy.org` |

改写方式：

```bash
git config --global url."https://ghfast.top/https://github.com/".insteadOf "https://github.com/"
```

要点：

- 该改写同时作用于 clone / fetch / push
- SSH 形式（`git@github.com:`）不受影响，需另行处理
- 部分通道会二次跳转（如 `hk.gh-proxy.com` 跳到 `.org`），git 会打印 `warning: redirecting to ...`，属正常现象

### 不改写也能用的通道

实测 `api.github.com`、`raw.githubusercontent.com`、`codeload.github.com` 通常仍可达。因此在不宜引入第三方通道的场景，可用下载归档代替 clone：

```bash
curl -L -o repo.zip https://codeload.github.com/<owner>/<repo>/zip/refs/heads/main
```

代价是没有 `.git` 历史。
