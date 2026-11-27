# 博客 · 原生 iOS 客户端

数据源 **[jable.tv](https://jable.tv)** 的纯原生 SwiftUI 客户端。外壳叫「博客」，图标是播客风紫色波纹，内核是完整的视频客户端。

- 目标：iPhone / iPad，iOS 15.0+
- 产物：`KanAV-unsigned.ipa`（未签名，自签安装）
- 构建：GitHub Actions 云端 macOS，约 4~6 分钟

---

## 一、为什么需要一个隐藏 WebView

jable.tv 挂在 **Cloudflare Turnstile** 后面，普通 HTTP 客户端拿到的永远是 `403 Just a moment...`。iOS 的 `URLSession` 没有 JS 执行环境，结构上过不了这道验证。

所以网络层是这样做的：

```
隐藏 WKWebView（2×2，不可见）
  → 加载目标页，真实 WebKit 环境自动过 Turnstile
  → 通过后 evaluateJavaScript 取 document.documentElement.outerHTML
  → 交给 Parser 解析
  → cookie 同步进 HTTPCookieStorage
     ↳ AVPlayer 拉 m3u8、下载分片时会带上 cf_clearance
```

界面完全是原生的，WebView 只在后台当传输层。验证通过后 `cf_clearance` 随 `WKWebsiteDataStore` 持久化，后续不再重复验证；28 秒没过会提示「站点人机验证未通过，请重试」。

## 二、功能

| 模块 | 说明 |
| --- | --- |
| 发现 | 8 个分类：最新 / 热门 / 新作 / 中文字幕 / 无码 / 破解马赛克 / 素人 / VR |
| 列表 | 双列网格（iPad 三列），封面固定高度，触底翻页 |
| 搜索 | `/search/{关键词}/` |
| 我的 | 最近观看（本地 60 条）、面容锁开关 |
| 播放 | HLS 原生播放，自定义控件全套 |

## 三、播放器

`AVPlayerViewController` 的控件改不了，整条链路是 `AVPlayerLayer` + 自绘 SwiftUI 控件层。

| 能力 | 实现 |
| --- | --- |
| HLS / MP4 | `AVURLAsset` + `AVPlayerItem`，请求带 Referer + CF cookie |
| 缓冲监听 | KVO `isPlaybackLikelyToKeepUp` / `bufferEmpty` + `PlaybackStalled` 通知 |
| 加载动画 | 中央菊花 + 底部「缓冲中」角标 |
| 错误提示 | 中文提示 + 重试 / 返回 |
| 进度条 | 自绘双层：半透明白=已缓冲，红=已播放，白点可拖带预览 |
| 手势 | 横滑 seek、左半屏亮度、右半屏音量、单击显隐面板 |
| 倍速 / 比例 / 循环 | 0.5~2×；适应/填充/拉伸；循环播放 |
| 音轨 / 内嵌字幕 | `AVMediaSelectionGroup`（`.audible` / `.legible`）— 片源自带轨道，不是翻译 |
| 画中画 | `AVPictureInPictureController(playerLayer:)` |
| 全屏 | 强制横屏，可退回内嵌；面板隐藏后左上角常驻返回键 |
| 状态回调 | `PlayerScreen(onStateChange:onProgress:)` |

## 四、面容锁

`LAContext` 生物识别：启动 App、从后台回前台自动上锁，开关在「我的 → 安全」，无 Face ID 设备退回密码。

## 五、代码结构

```
KanAV/Sources/
├─ KanAVApp.swift                 # 入口 + Tab + 锁屏覆盖
├─ Core/
│  ├─ Models.swift                # 站点常量、分类、VideoItem
│  ├─ WebFetcher.swift            # 隐藏 WKWebView 过 Cloudflare + cookie 同步
│  ├─ Net.swift                   # 先直连、失败转 WebFetcher
│  ├─ Parser.swift                # /videos/{slug}/ 锚点式解析 + m3u8 提取
│  ├─ HistoryStore.swift
│  └─ AppLock.swift               # 面容 / 触控 ID 锁
├─ Playback/
│  ├─ PlayerEngine.swift
│  └─ PiPManager.swift
└─ Views/
   ├─ HomeView / SearchView / LibraryView / VideoCard
   └─ Player/
      ├─ PlayerScreen.swift  PlayerControls.swift  PlayerGestureLayer.swift
      ├─ PlayerSurface.swift  OrientationSupport.swift
```

## 六、打包成 IPA

Actions → **Build IPA** → Run workflow，完成后在运行页底部 **Artifacts → KanAV-unsigned-ipa** 下载。
推 `v*` tag 会自动把 IPA 挂到 Release。

本地 macOS：`brew install xcodegen && bash tools/build_ipa.sh`。

## 七、装到 iPhone

Sideloadly / AltStore / 爱思助手 自签安装；免费 Apple ID 签名 7 天有效。
首次打开提示不受信任：设置 → 通用 → VPN与设备管理 → 信任。

## 八、常见问题

**Q：一直提示「站点人机验证未通过」？**
Cloudflare 对出口 IP 敏感。换网络（家宽 / 5G）各试一次；仍不行说明该 IP 被 CF 要求交互式验证，只能换线路。

**Q：列表能出但封面是空的？**
封面走 `static.javcdn.vip`，可能被单独限速；下拉重试即可。

**Q：点开视频提示解析不出播放地址？**
jable 换模板了。抓一份播放页 HTML，看 `hlsUrl` 的实际变量名，补到 `Parser.playSource` 的候选列表即可。

**Q：改站点？**
`Core/Models.swift` 的 `Site.base`、`Site.categories`；解析规则在 `Parser.swift`。
