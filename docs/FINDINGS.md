# 研究记录：不 Root 的中兴 F50（内置卡版）上运行 mihomo

测试设备：中兴 F50 / MU300，**内置卡版**，固件 `MU300_STESIMV1.0.0B03`（`ro.build.display.id = F50_ST_ESIMV1.0.0B03`，
2025-10-15 构建，Android 13），64 GB eMMC（`/data` 约 54.9 GB）。下面的结论只在这一台、这一版固件上实测过。

## 1. 设备状态：锁定、无 Root

开机后短暂的 ADB 窗口（见第 3 节）里读到：

| 项目 | 值 |
|---|---|
| `ro.product.model` / `device` | `F50` / `MU300` |
| `ro.boot.slot_suffix` | `_a` |
| `ro.boot.flash.locked` | `1` |
| `ro.boot.vbmeta.device_state` | `locked` |
| `ro.boot.verifiedbootstate` | `green` |
| `su` | 不存在，`/data/adb` 无权限 |

Bootloader 锁定、验证启动为 green，只能启动 ZTE 签名的系统。

## 2. 原厂后台：隐藏的 USB 端口开关与 goform 接口

* 后台 `http://192.168.0.1`，默认密码 `admin`。前端是 `js/config/ufi/MU5002/` 这一套。
* 菜单里有不显示的页面：`#usb_port`（"USB 端口"开关）、`#usb_internet_protocol`、`#sim_switch`（内置卡在"电信/移动"之间切换，
  `sim_slot` 0/1，`dual_sim_support=1`）、`#network_debug` 等。在浏览器里直接打开 `index.html#usb_port` 有时显示不出来，用接口更可靠。
* 登录与写操作（`WEB_ATTR_IF_SUPPORT_SHA256 = 2`）：
  * `LOGIN`：`password = SHA256(SHA256(明文) + LD)`，十六进制大写，`LD` 来自 `goform_get_cmd_process?cmd=LD`；
  * 每个写命令带 `AD = SHA256(SHA256(wa_inner_version + cr_version) + RD)`，`RD` 每次现取。
* `USB_PORT_SETTING usb_port_switch=1` 打开 USB 端口开关；`REBOOT_DEVICE` 重启。实现见 `scripts/zte-web.py`。
* 不登录也能读 `cr_version`、`wa_inner_version`，可以先用来判断固件版本。

## 3. ADB 只有开机后约 10 秒

打开开关后重启，USB 先以 `19d2:1352`（纯 adb）出现，`persist.sys.usb.config=adb`、adbd 运行；大约 10 秒后变回
`19d2:1353`（ECM 网卡 + MTP），ADB 消失。抓到的系统日志：

```
UsbDeviceManager: UsbDeviceManager: bAllowAdbEnable: false
UsbDeviceManager: receive system state=CONNECTPC
UsbDeviceManager: rev MSG_DELAYED_TO_SET_USB_CONFIG                 (约 5 s 之后)
UsbDeviceManager: setEnabledFunctions functions=4100 ...
UsbDeviceManager: Setting USB config to ecm,mtp
```

* 开关由 ZTE 改过的 `UsbDeviceManager` 控制，依据是 bootloader 传入的 **`ro.boot.qrcode_adb_allow=false`**，用户层改不了。
  公开教程里"B09 能开 ADB"在这版内置卡固件上不成立。
* USB 切到 `ecm,mtp` 时 init 会**停掉 adbd**，它的子进程一并被杀：
  * `adb tcpip 5555` 能切换成功，但 USB 一切走，`192.168.0.1:5555` 就是 `Connection refused`；
  * 在窗口里 `nohup` 留后台进程也活不下来（同一个服务 cgroup）。
* 窗口很早：前几秒连 `settings` 服务都没有（`Can't find service: settings`），过早的 `pm install` 会抛
  `Cannot access system provider: 'settings' before system providers are installed`，`am start` 报 `Too early to start activity`。
  等到 `sys.boot_completed=1` 再做，`pm install` 一个 27 MB 的 APK 约 2–4 秒，`am start` 也来得及。
* 窗口期里 `/sdcard`（共享存储）**还没挂载**，所以 ADB 读不到应用的外部目录。

## 4. 为什么没有走 Root / OpenWrt 路线

* [mu300-linux](https://github.com/dikeckaan/mu300-linux)（Ubuntu/OpenWrt）要求设备**已解锁并 Root**、Android 在 slot a。
  它的 SD 卡模式只写 `boot_b` 和 `misc` 的 32 字节，本身很克制，但前提条件这台设备不满足。
* 公开的 Root 路线 [zte-f50-toolkit](https://github.com/dikeckaan/zte-f50-toolkit) 只针对 **B09**（插卡版 FLYMODEM 固件）：
  经 SPD/BROM 把整机降级为 B09，再刷打过补丁的 `trustos` 和 Magisk boot。它的 B09 包会写入
  `splloader`、`uboot`、`trustos`、`vbmeta*`、`nr_modem`/`nr_phy`、`super`，以及 **`miscdata`、`ztepersist`**（另一台设备的数据），并清空 userdata。
* B09 的 vbmeta：`rollback_index = 0`，系统指纹 `.../20250120.095956`，安全补丁 2025-01-05；内置卡 B03 是 2025-10-15 构建，
  另一条产品线。设备当前存的回滚索引无法在不 Root 的情况下读出；内置卡在 B09 上还能否使用也没有资料。
* mu300-linux 没有内置卡/eSIM 支持（其 issue #1：作者手上的设备都是实体卡）。
* 结论：在内置卡版上 Root 需要冒覆盖设备专属数据和变砖的风险，而且装好 Linux 后蜂窝网络也大概率不可用，因此改走不 Root 的路线。

## 5. 不 Root 的做法：一个无界面的 APK

* 现成的安卓 Clash/mihomo 客户端都要在屏幕上点"启动"和"允许 VPN"，F50 没有屏幕，ADB 又只有 10 秒，所以自己写了一个极简 APK（`app/`）：
  * mihomo 的 android-arm64 版放在 `lib/arm64-v8a/libmihomo.so`，`extractNativeLibs=true`，从 `nativeLibraryDir` 执行
    （该 mihomo 由 NDK 按 API 34 构建，但只依赖基础 `LIBC` 符号版本，在 Android 13 上能跑）；
  * 前台服务 + `PARTIAL_WAKE_LOCK`，mihomo 退出后自动重启（2 s 起，最长 60 s 退避）；
  * `BOOT_COMPLETED` 接收器开机自启；新装的应用处于 stopped 状态收不到开机广播，所以安装后要 `am start` 一次；
  * 安装时 `cmd deviceidle whitelist +local.f50mihomo`，避免无屏设备进入 Doze 后断网。
* 不用 TUN/VpnService：普通应用拿不到 `CAP_NET_ADMIN`，VpnService 只管本机流量（热点客户端的流量不经过它），还要屏幕上授权。
  所以只能做 HTTP/SOCKS 代理，客户端自己设置代理。
* 实测：开机后约 70 秒（移动数据连上 + mihomo 启动）代理可用，无需任何操作；手动选的节点重启后保留（`profile.store-selected`）。
* 构建不需要 Gradle：`aapt2` + `javac` + `d8` + `zipalign` + `apksigner`（`scripts/build.sh`）。`android.jar` 里没有 `LambdaMetafactory`，
  所以代码里不用 lambda。

## 6. 端口与访问控制

* **9090 被 ZTE 自己的服务占用**（开机时、应用启动前 `netstat` 就能看到 `[::]:9090 LISTEN`），mihomo 的控制接口绑不上。改用 **19090**。
* ZTE 的防火墙放行局域网客户端连到应用监听的端口（7890/7891/19090 都能从 USB 和 Wi-Fi 客户端访问）。
* 设备在移动网络上有公网 IPv6 地址，所以配置里用 `lan-allowed-ips` 只允许私有地址使用代理，局域网免认证（`skip-auth-prefixes`），
  控制接口加密钥。外网方向是否真的连不进来没有做端到端测试。
* 日志：私有目录 ADB 读不到，共享存储窗口期又没挂载，于是把日志放在面板目录下以密钥命名的子目录里：
  `http://192.168.0.1:19090/ui/<密钥>/mihomo.log`。不带密钥的路径返回 404。

## 7. 网络：这张卡上多数代理服务器连不上

* 设备只有一个网络：`sipa_eth0`，CELLULAR，IPv4 是运营商 NAT 内网地址（10.x/32），另有一个公网 IPv6 /64；本机应用和热点客户端走同一条线路。
* 本机直连 Cloudflare、portquiz.net 的 80/443/8443/11119/36712 端口都正常，DNS 解析与 DoH 一致（没有被污染）。
* 但测试用配置里的多数服务器，**新建 TCP 连接一律超时**（应用里用 Java `Network.bindSocket` 逐个网络测，以及从电脑经 F50 转发测，结果相同）；
  只有两台服务器能连。看起来是这张卡所在网络按目的 IP 拦截，与设备、端口、协议无关。要用哪个节点，以在 F50 上实测为准。
* 测试时的坑：电脑上开着 FlClash（TUN + fake-ip），`curl --interface`、`/dev/tcp` 的"直连"和域名解析都会被它截走，
  得到 1 ms 的假连接或 198.18.x 的假地址。可靠的办法是绑定源地址并直接用 IP，或者干脆在 F50 上测。

## 8. 配置上的两个坑

* **url-test 组里放了 DIRECT**：测速地址 `www.gstatic.com/generate_204` 在国内直连就能访问，DIRECT 测出来最快，组就自动选了直连，
  国外网站全部打不开。`scripts/prepare-config.py` 会把 DIRECT 从 url-test/fallback 组里拿掉；也可以用 `--manual` 改成手动选择。
* 刚启动时整组并发测速经常"全部超时"，单个节点测却正常；组在拿到第一个成功结果之前会用第一个成员。手动选择组更可预期。

## 9. 客户端

* iPhone：Wi-Fi → 配置代理 → **手动** `192.168.0.1:7890` 可用；同一页的"自动"填 `http://192.168.0.1:19090/ui/proxy.pac`
  这次**没有生效**（文件能下载，`Content-Type: text/plain`，原因未查）。
* 面板是 metacubexd：`http://192.168.0.1:19090/ui`。直接打开 `:19090/` 看到的是 API（`{"message":"Unauthorized"}`）。
  面板默认后端是 `http://127.0.0.1:9090`，要改成 `http://192.168.0.1:19090`（`build.sh` 已经把它设成默认值）。
