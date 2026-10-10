# zte-f50-mihomo

**在不 Root、不解锁的随身 WiFi 上跑 mihomo，让它成为随身的旁路由（不是透明网关）。**

* 设备：中兴 F50 随身 WiFi。用一个自己写的无界面安卓应用跑 [mihomo](https://github.com/MetaCubeX/mihomo)，开机自启，
  提供 HTTP/SOCKS 代理（`192.168.0.1:7890`）和网页管理面板（metacubexd）。
* **旁路由，不是透明网关**：F50 仍然是原厂路由器，连上 Wi-Fi 默认直连；**要翻墙的设备需要自己把代理设为 `192.168.0.1:7890`**，
  设置方法见[手机和电脑的网络设置](#手机和电脑的网络设置)。
* 原厂系统、5G、内置卡都不动，卸载即复原。

研究过程和每个结论的依据见 [docs/FINDINGS.md](docs/FINDINGS.md)。

> 个人折腾项目，没有任何担保。请遵守当地法律和运营商条款。只在一台内置卡版 F50（固件 `F50_ST_ESIMV1.0.0B03`）上实测过。

---

## 先确认你的 F50 是哪一版

F50 有两种：

| | **插卡版** | **非插卡版（内置卡 / eSIM 版）** |
|---|---|---|
| 外观 | 有实体 SIM 卡槽 | 没有卡槽，内置运营商卡，后台可在"电信/移动"之间切换 |
| 固件版本字样 | `F50_FLYMODEM_ZYV1.0.0Bxx`（常见 B09） | `F50_ST_ESIMV1.0.0Bxx`（本项目测试的是 B03） |
| 原厂后台开 ADB（`#usb_port`） | 社区报告 B04–B09 可以正常开 | 只在开机后约 10 秒可用，之后被系统强制关闭（`ro.boot.qrcode_adb_allow=false`） |
| Root / 解锁 | 有公开路线：[zte-f50-toolkit](https://github.com/dikeckaan/zte-f50-toolkit) 降级到 B09 后刷 Magisk / 解锁 | 没有对应的公开路线；套用 B09 降级包会覆盖 `miscdata`、`ztepersist` 等设备专属数据和整条启动链，内置卡能否继续使用未知 |
| 能装完整 Linux（OpenWrt / Ubuntu） | 能：Root 后用 [mu300-linux](https://github.com/dikeckaan/mu300-linux)，可做 TUN 透明代理 | 不能（需要先 Root；mu300-linux 也不支持内置卡） |

怎么看版本：浏览器打开 `http://192.168.0.1` 登录后在设备信息里看，或者运行 `python3 scripts/zte-web.py status`，看 `wa_inner_version`。

### 该怎么选

* **插卡版**
  * 想要完整的路由器（OpenWrt、全局透明代理、所有设备无需设置）：按 mu300-linux 和 zte-f50-toolkit 的文档 Root 后安装。
    这条路要刷底层，有变砖风险，先做全量备份。
  * 不想刷机：本项目理论上也能用（ADB 更稳定，安装更容易），但**未在插卡版上实测**。
* **非插卡版（内置卡）**：用本项目。只装一个普通应用，不碰分区，不需要解锁。代价是没有 TUN，每台设备要自己设置代理。
* **两种都适用、最省心的办法**：F50 保持原厂，只负责上网；后面用 USB 或网线接一台 OpenWrt 小路由器（GL-MT3000、Cudy TR3000 等）跑 mihomo/OpenClash 的 TUN。

---

## 本项目能做什么，不能做什么

* ✅ 开机自动运行 mihomo，局域网设备（Wi-Fi、USB）通过 `192.168.0.1:7890` 使用代理，国内直连、国外走节点（按你的规则）
* ✅ 网页面板 `http://192.168.0.1:19090/ui`：选节点、看连接和日志
* ✅ 重启后自动恢复（实测开机约 70 秒可用），手动选的节点会保留
* ❌ 没有 TUN / 透明代理：手机、电脑要自己设置 HTTP 代理；不支持代理设置的设备和应用（部分游戏、电视）走不了
* ❌ 改配置或升级 mihomo 要重新打包，再通过开机 ADB 窗口安装（约 1 分钟，期间 F50 会重启）
* ⚠️ 你的节点在 F50 那张卡的网络上不一定连得通。实测这张卡会按 IP 拦截多数代理服务器，以面板里的测速为准

## 安装

需要一台 Linux 电脑（macOS 应该也行，未测），F50 用 USB 连着，电脑能打开 `http://192.168.0.1`。
还需要 Python 3（带 PyYAML）、`curl`、`unzip`、`zip`，以及 JDK 17（例如 `mise install java@temurin-17`）。

```sh
export JAVA_HOME=/path/to/jdk-17

# 1. 准备工具和依赖（都下载到项目目录里，不需要 root）
scripts/setup-sdk.sh                 # adb + Android build-tools + platform 33 → .sdk/
scripts/fetch-deps.sh                # mihomo、metacubexd、Country.mmdb → deps/（固定版本，校验 SHA256）

# 2. 打开原厂后台的 USB 端口开关（等同于在 index.html#usb_port 里打开）
ZTE_PASSWORD=admin python3 scripts/zte-web.py adb-on

# 3. 用你自己的 mihomo/Clash 配置生成 F50 用的配置
python3 scripts/prepare-config.py ~/my-mihomo.yaml --secret 你的面板密码
#   可选：--manual '节点选择'          把某个自动测速组改成手动选择
#         --first '节点选择=某个节点'   设置手动选择组的默认节点

# 4. 打包并安装
scripts/build.sh                     # → out/f50-mihomo.apk
scripts/window-install.sh            # 重启 F50，在开机 ADB 窗口里安装并启动
```

`window-install.sh` 会通过原厂后台重启 F50，等 ADB 出现、系统启动完成后，用几秒钟完成安装、加入省电白名单、首次启动。
一轮没来得及会自动重试（最多 5 轮）。

## 工作方式：局域网里的一台代理服务器，不是网关

F50 本身仍然是原厂路由器：DHCP、网关、DNS 都还是 ZTE 的，设备连上 Wi-Fi 后默认**直接上网，不经过 mihomo**。
本项目只是在 F50 上多跑了一个代理服务（`192.168.0.1:7890`），用法和"旁路由"类似：**谁想翻墙，谁自己把代理指向它**。

```
手机/电脑 ──Wi-Fi/USB──> F50（原厂路由，网关 192.168.0.1）──5G──> 互联网
     │                          ▲
     └─ 设置了代理的应用 ──> mihomo :7890 ──（国内直连 / 国外走节点）
```

* 没设置代理的设备、不走系统代理的应用：照常直连，国内能用，国外打不开。
* 设置了代理的：按你配置里的规则分流，国内直连，国外走节点。
* 想要所有设备都不用设置：F50 做不到（没有 Root 就没有 TUN 和 iptables），见上面"该怎么选"里的外接 OpenWrt 路由器方案。

## 手机和电脑的网络设置

先连上 F50 的 Wi-Fi（或用 USB 连接）。代理地址都一样：**服务器 `192.168.0.1`，端口 `7890`，不需要用户名和密码**
（同一端口也支持 SOCKS5；`7891` 是单独的 SOCKS5 端口）。

| 系统 | 设置位置 |
|---|---|
| **iPhone / iPad** | 设置 → 无线局域网 → F50 的 Wi-Fi 右边的 ⓘ → 最下面"配置代理" → **手动** → 服务器 `192.168.0.1`，端口 `7890`，鉴定关 → 存储 |
| **安卓** | 设置 → WLAN → 长按或点开 F50 的 Wi-Fi → 修改网络 / 高级选项 → 代理：**手动** → 主机名 `192.168.0.1`，端口 `7890` → 保存（各品牌菜单名略有不同） |
| **Windows 10/11** | 设置 → 网络和 Internet → 代理 → 手动设置代理 → 打开，地址 `192.168.0.1`，端口 `7890`，勾选"请勿将代理服务器用于本地地址" → 保存 |
| **macOS** | 系统设置 → 网络 → F50 的 Wi-Fi（或 USB 网卡）→ 详细信息 → 代理 → 打开"网页代理 (HTTP)"和"安全网页代理 (HTTPS)"，都填 `192.168.0.1` : `7890` |
| **Linux 桌面** | 设置 → 网络 → 网络代理 → 手动，HTTP/HTTPS 都填 `192.168.0.1` : `7890`；命令行用 `export https_proxy=http://192.168.0.1:7890 http_proxy=http://192.168.0.1:7890` |

验证：浏览器打开 `https://www.google.com` 能打开、`https://www.baidu.com` 也正常即可。面板"连接"页能看到来自这台设备 IP 的连接。

注意：

* 代理设置是**跟着 Wi-Fi 走的**（手机）或跟着网卡走的（电脑）。离开 F50 的 Wi-Fi 后，手机上这项设置不影响别的网络；但电脑的全局代理要记得关掉，否则换了网络会上不了网。
* 系统代理只对**遵守系统代理的应用**有效：浏览器、大多数 App 都可以；部分游戏、视频客户端、命令行程序不走系统代理。
* 已经装了 Clash / Shadowrocket 这类客户端的手机，也可以把 F50 当作上游：在客户端里加一个 `socks5 192.168.0.1:7891` 或 `http 192.168.0.1:7890` 的节点。
* "自动配置代理（PAC）" 的地址是 `http://192.168.0.1:19090/ui/proxy.pac`，但在 iPhone 上实测没有生效，建议用手动。
* F50 开机后约 1 分钟代理才可用，这段时间设置了代理的设备会暂时上不了网。

## 使用

* **面板**：浏览器打开 **`http://192.168.0.1:19090/ui`**（结尾的 `/ui` 不能少；`:19090/` 是 API，会显示 `Unauthorized`）。
  后端地址 `http://192.168.0.1:19090`，密钥是你在第 3 步设置的。在"代理"页面测速、选节点。
* **手机 / 电脑**：每台设备都要设置代理，见上面"手机和电脑的网络设置"。
* **日志**：`http://192.168.0.1:19090/ui/<你的密钥>/mihomo.log`
* **改配置**：重新执行第 3、4 步。签名密钥保存在 `.keys/` 里，别删，否则新包无法覆盖安装。

## 卸载

```sh
scripts/window-shell.sh 'pm uninstall local.f50mihomo'
python3 scripts/zte-web.py adb-off     # 可选：关掉 USB 端口开关
```

## 安全

* 只有私有网段的地址能使用代理（`lan-allowed-ips`），其他来源会被拒绝。F50 在移动网络上有公网 IPv6，这一条很重要。
* 面板和 API 需要密钥。面板的静态页面本身不需要密钥。
* APK 里打包了你的配置（包括节点密码）。不要把 `out/`、`build/`、`.keys/` 和你的配置文件传到公开的地方，`.gitignore` 已经把它们排除了。

## 目录

```
app/                     安卓应用源码（Java，无第三方依赖）
  MihomoService.java     前台服务：释放资源、运行 mihomo、崩溃后重启
  BootReceiver.java      开机自启
  MainActivity.java      首次启动用的空 Activity
config/
  config.example.yaml    示例配置（占位节点）
  proxy.pac              PAC 文件
scripts/
  zte-web.py             原厂后台：状态、开关 ADB、重启
  setup-sdk.sh           下载 adb 和 Android 构建工具
  fetch-deps.sh          下载 mihomo、metacubexd、GeoIP 数据库
  prepare-config.py      把你的配置改成 F50 能用的
  build.sh               打包签名 APK（不用 Gradle）
  window-install.sh      在开机 ADB 窗口里安装
  window-shell.sh        在开机 ADB 窗口里执行一条命令
docs/FINDINGS.md         研究记录
```

## 致谢

* [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo)（GPL-3.0）、[metacubexd](https://github.com/MetaCubeX/metacubexd)、[meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat)：
  构建时下载，不在本仓库中分发。
* [dikeckaan/mu300-linux](https://github.com/dikeckaan/mu300-linux)、[dikeckaan/zte-f50-toolkit](https://github.com/dikeckaan/zte-f50-toolkit)、
  [kanoqwq/UFI-TOOLS](https://github.com/kanoqwq/UFI-TOOLS)：F50 的硬件资料和社区经验。

本仓库的代码以 MIT 许可证发布，见 [LICENSE](LICENSE)。
