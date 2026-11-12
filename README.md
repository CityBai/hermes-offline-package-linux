# Hermes Agent 离线安装包（Linux x86_64）

> 给国内内网 / 断网 / 网络环境不好的 Linux 服务器准备的一键离线安装包。
> 不需要 uv，不需要 pip，不需要 npm，也不需要系统里预装 Python 3.11。

Hermes Agent 是 [Nous Research](https://github.com/NousResearch/hermes-agent) 开源的 AI Agent 框架。它的官方安装脚本要连着访问好几个境外站点——下载 uv、拉 Python 3.11、装 100 多个 pip 依赖、再装 npm 包和 Chromium。在国内网络环境下，这套流程经常卡在某一步，甚至在内网机器上根本走不通。

这个项目基于完整部署的linux版hermes agent把整条链路打完包：**解压、跑一个脚本、装完就能用。**

---

## 包里有什么

| 组件 | 大小 | 说明 |
|---|---|---|
| Python 3.11.15 解释器 | 101 MB | 独立解释器，与系统 Python 完全隔离 |
| Python 虚拟环境 | 571 MB | 117 个预装依赖（含 Playwright、openpyxl、httpx 等） |
| Node.js v22.23.1 | 199 MB | TUI 和桌面版运行时 |
| npm 依赖 | 345 MB | 324 个包，含已构建的 TUI 渲染组件 |
| Chromium 浏览器 | 656 MB | Playwright 用，开箱即可跑浏览器自动化 |
| Hermes 源码 | 651 MB | v0.21.3，含内置技能和插件 |

压缩包约 **646 MB**，解压后约 **2.1 GB**，安装后占约 **2.1 GB**。


---

## 快速开始

```bash
# 1. 从 Releases 页面下载
#    hermes-offline-20261111-x86_64.tar.gz

# 2. 解压
tar xzf hermes-offline-20261111-x86_64.tar.gz
cd hermes-offline

# 3. 安装（需要 root）
sudo ./install.sh
```

装到 `/opt/hermes`，命令软链到 `/usr/local/bin/hermes`。

要换路径：

```bash
sudo HERMES_PREFIX=/data/hermes ./install.sh
```

装完之后：

```bash
hermes setup      # 配置模型和 API key（这一步需要联网）
hermes            # 开始对话
hermes gateway    # 启动消息平台网关
hermes --tui      # 终端界面
```

> **注意**：安装过程完全离线，但 `hermes setup` 配置 API key 时需要网络。如果目标机彻底不通外网，先在有网机器上配好 `config.yaml` 和 `.env`，再拷过去。

---

## 环境要求

| 项 | 要求 | 说明 |
|---|---|---|
| 架构 | **x86_64** | ARM（鲲鹏 / 飞腾）需要自行在 ARM 机器上重新构建 |
| glibc | **≥ 2.28** | 麒麟 V10、CentOS 8、Ubuntu 20.04+ 都可以；**CentOS 7（2.17）不行** |
| 磁盘 | **≥ 6 GB** | 包 + 解压 + 安装 |
| 权限 | root | 要写 `/opt` 和 `/usr/local/bin` |

安装脚本会先检查架构、glibc、磁盘空间，不满足直接报错退出，不会装一半。

已验证：CentOS 8.2 / Kylin V10 SP3（x86_64）。

---

## 安装脚本做了什么

```
[1/7] 环境检查     架构 / glibc / 磁盘 / 安装包完整性
[2/7] 释放文件     解到目标路径，已有安装自动备份
[3/7] 重定位 venv  改写 pyvenv.cfg、脚本 shebang、模块路径映射
[4/7] 依赖校验     实际 import 10 个关键模块
[5/7] 浏览器       部署 Playwright Chromium
[6/7] 命令入口     /usr/local/bin/hermes 软链
[7/7] 端到端自检   hermes --version + hermes doctor
```

任何一步失败都会明确报错，不会留下半装状态。

---

## 几个容易踩的坑（也是这个包存在的原因）

**1. venv 是 editable 安装，模块路径写死在构建机的位置**

Hermes 的虚拟环境用 `pip install -e` 装的，所有包路径以绝对路径形式存在
`venv/lib/python3.11/site-packages/__editable___hermes_agent_*_finder.py` 里。

直接复制 venv 到别的机器，`import hermes_cli` 还是去原路径找代码——目标机上没这个目录就 import 失败。而且**在构建机上测试一切正常**，极具欺骗性。

安装脚本会自动探测并改写这个映射。

**2. TUI 的依赖不在 `ui-tui/` 目录下**

`ui-tui/package.json` 的依赖走 npm workspace，实际落在仓库根的 `node_modules/`。
`ui-tui/node_modules/` 里只有两个包，看着像没装依赖，其实是正常的。

另外 TUI 的渲染组件需要预先构建（`npm run build:ink`），产物在
`ui-tui/packages/hermes-ink/dist/`。不打进去的话，首次启动 `hermes --tui` 会尝试联网 npm install。

**3. 各种检测写法的细节**

- glibc 用 `getconf GNU_LIBC_VERSION` 取，`ldd --version | head -1` 在部分系统上会带换行
- 在 `set -o pipefail` 下，`VAR=$(cmd | head -1) || die` 会因 `head` 提前关闭管道导致 cmd 收到 SIGPIPE，被误判成失败

---

## 自己重新构建

如果你想基于自己机器上的 Hermes 重新打包：

```bash
# 修改 build.sh 顶部的源路径，然后
./build.sh
```

产出 `hermes-offline-<日期>-x86_64.tar.gz`。

只改了 `install.sh` 的话，不用重跑整个构建：

```bash
cp install.sh hermes-offline/install.sh
tar czf hermes-offline-<日期>-x86_64.tar.gz hermes-offline
```

构建脚本假设源环境是：

- Hermes 装在 `/usr/local/lib/hermes-agent`（含 `venv/` 和 `node_modules/`）
- uv 管理的 Python 在 `/usr/local/share/uv/python/`
- Node 在 `$HERMES_HOME/node`

路径不同的话改 `build.sh` 开头的几个变量即可。

---

## 踩坑记录

跨机器分发包最容易死在符号链接上。下面几个坑都是实际安装时踩到的，**构建机上永远复现不了**——链接在构建机上是通的，只有干净的目标机才会暴露。

### 1. `venv/bin/python` 指向构建机绝对路径

uv 创建的 venv 里，`venv/bin/python` 是指向构建机 Python 的绝对路径符号链接：

```
app/venv/bin/python -> /usr/local/share/uv/python/cpython-3.11-linux-x86_64-gnu/bin/python3.11
```

目标机上这个路径不存在，整条链断掉，venv 起不来。

**处理**：包内改成相对链接 `../../../../python/cpython-3.11-linux-x86_64-gnu/bin/python3.11`，`install.sh` 安装时再重建一次并重写 `pyvenv.cfg`。

### 2. 用 `-x` 检查符号链接会误报

```bash
[ -x "$VENV/bin/python3" ] || die "venv 里没有 python3，包有问题"
```

`-x` 遇到断链一律返回假。这个检查如果放在重建链接**之前**，无论真实原因是链接没建好、还是 `python/` 目录没拷全，都报同一句"包有问题"，指不到病因。

**处理**：先验证包内解释器本体存在，再重建链接，最后才验可执行；失败时打印 `readlink -f` 的解析结果。

### 3. `cp -a` 可能漏掉大目录

现象是 `[2/7] 已释放 1.4G`，而正常接近 2 GB。此时 `python/` 没拷全。

**排查**：

```bash
du -sh ./python /opt/hermes/python     # 两个数应该一致
```

不一致就手动补拷后重建链接：

```bash
cp -a python /opt/hermes/python
VENV=/opt/hermes/app/venv
PYBIN=/opt/hermes/python/cpython-3.11-linux-x86_64-gnu/bin/python3.11
ln -sfn "$PYBIN" "$VENV/bin/python"
ln -sfn "python" "$VENV/bin/python3"
ln -sfn "python" "$VENV/bin/python3.11"
$VENV/bin/python3 --version
```

### 教训

改完 `install.sh` 一定要在**干净的目标机**上实测一遍。构建机自测通过说明不了任何问题。

---

## 版本

本包基于 **hermes-agent v0.21.3**（2026.9.14，upstream `dec236b2`）构建。

装完之后 `hermes update` 仍然可以用（需要联网），但离线状态下就是这个版本。

---

## License

本项目的构建脚本和安装脚本以 MIT 协议发布，详见 [LICENSE](LICENSE)。

内置的 Hermes Agent 源码版权归 [Nous Research](https://github.com/NousResearch/hermes-agent) 所有，同样为 MIT 协议，原始许可证随包分发。

本项目只是提供一个离线分发与安装的封装方案，不是 Hermes Agent 的官方发行版，也与 Nous Research 无隶属关系。
