# KanAV · 原生 iOS 客户端

站点 [kanav.ad](https://kanav.ad) 的**纯原生** SwiftUI 客户端：不带 WebView，不套壳网页。
列表、搜索、播放全部走原生控件，视频交给 `AVPlayerLayer` + 自绘控件层，另附端上实时字幕翻译。

- 目标：iPhone / iPad，iOS 15.0+
- 产物：`KanAV-unsigned.ipa`（未签名，自签安装）
- 构建：GitHub Actions 云端 macOS，约 3~6 分钟

---

## 一、为什么不是网页壳

站点没有开放 JSON 接口（`/api.php/provide/vod` 返回 `closed`，`/index.php/api/vod` 404），
所以数据走 HTML 抓取 + 正则解析；但播放地址是可解的：

```
player_aaaa.url  --base64-->  %68%74%74%70%73...  --url decode-->  https://cdn14.11yun.space/xxx.m3u8
```

解析出来就是标准 HLS 直链，无 DRM、无需 Referer，`AVPlayer` 原生播放。
解析规则全部集中在 `Parser.swift`，站点换模板只改这一个文件。

## 二、功能

| 模块 | 说明 |
| --- | --- |
| 发现 | 14 个分类横向切换（最新/中文字幕/日韩有码/日韩无码/国产/自拍/泄密/探花/主播/动漫/里番/Motion/3D/同人） |
| 列表 | 双列网格，触底自动翻页，封面懒加载，右下角显示时长 |
| 搜索 | 番号 / 片名 / 演员关键词，直接解析站点搜索结果页 |
| 最近观看 | 本地记录最近 60 条，可单条移除或清空 |

## 三、播放器

`AVPlayerViewController` 的控件改不了，所以整条播放链路是 `AVPlayerLayer` + 自绘 SwiftUI 控件。

| 能力 | 实现 |
| --- | --- |
| HLS / MP4 远程流 | `AVURLAsset` + `AVPlayerItem`，`m3u8`、`mp4` 统一走 AVPlayer |
| 缓冲监听 | KVO `isPlaybackLikelyToKeepUp` / `isPlaybackBufferEmpty` + `AVPlayerItemPlaybackStalled` 通知，状态机 idle/loading/playing/paused/buffering/ended/failed |
| 加载动画 | 中央菊花 + 底部「缓冲中」角标（只在缓冲时出现） |
| 错误提示 | `item.error` / `FailedToPlayToEndTime` 转成中文提示 + 重试按钮 |
| 进度条 | 自绘双层：半透明白=已缓冲，红色=已播放，白点可拖，拖动时显示预览时间 |
| 时间展示 | `00:00 / 1:58:04`，小时位自动出现，等宽数字防抖动 |
| ±15 秒 | `gobackward.15` / `goforward.15` |
| 全屏 | 自绘按钮 + `UIWindowScene.requestGeometryUpdate` 强制横屏（iOS 16+），退回内嵌时锁回竖屏 |
| 手势 | 横滑 seek（整屏宽=120 秒）、左半屏上下调**亮度**、右半屏上下调**音量**（`MPVolumeView`）、单击显隐面板、3.5 秒自动隐藏 |
| 倍速 | 0.5 / 0.75 / 1 / 1.25 / 1.5 / 1.75 / 2，切换时保持当前速率 |
| 画面比例 | 适应 / 填充 / 拉伸三档循环 |
| 循环播放 | `AVPlayerItemDidPlayToEndTime` 后 seek 到 0 续播 |
| 画中画 | `AVPictureInPictureController(playerLayer:)`，需要 Background Modes → Audio（已配置） |
| 音轨 / 字幕 | `AVMediaSelectionGroup`（`.audible` / `.legible`），菜单里列出全部轨道，可关闭内嵌字幕 |
| 锁屏常亮 | 播放页 `isIdleTimerDisabled`，离开恢复 |
| 状态回调 | `PlayerScreen(onStateChange:onProgress:)` 把播放状态和进度抛给上层页面 |

## 四、实时字幕翻译

「把外语片直接看成中文」这条链路是**全端上**跑的：

```
AVPlayerItem.audioMix
  └─ MTAudioProcessingTap（PostEffects，拿解码后 PCM，不额外起播放、不占带宽）
       └─ SFSpeechAudioBufferRecognitionRequest（ja-JP / zh-CN / en-US，on-device 优先）
            └─ Translation framework（iOS 18+，端上翻译，免费无网）
              ↳ 兜底：OpenAI 兼容接口（自填 endpoint / key）
                 └─ 双语字幕层（译文大、原文小）
```

播放页控制条右侧 `character.bubble` 按钮开关，状态用 Toast 提示（无权限 / 语言不支持 / 已开启）。

已知限制：

- 系统识别单次任务约 1 分钟会被掐断，代码里 45 秒自动换任务续接；
- 日语/中文离线语言包需先在系统里下载，否则识别走网络或直接失败；
- 同类片源旁白少、环境音多，识别准确率天然偏低，字幕会断续；
- 端上翻译要 iOS 18+；低版本只走在线接口兜底。

## 五、代码结构

```
KanAV/Sources/
├─ KanAVApp.swift                 # App 入口 + 三个 Tab + 配色
├─ Core/
│  ├─ Models.swift                # 站点常量、分类、VideoItem
│  ├─ Net.swift                   # URLSession（UA / Referer / 超时）
│  ├─ Parser.swift                # HTML 卡片解析 + player_aaaa 解密
│  └─ HistoryStore.swift          # 最近观看
├─ Playback/
│  ├─ PlayerEngine.swift          # 状态机 / 缓冲 / 倍速 / 循环 / 音轨字幕轨
│  └─ PiPManager.swift            # 画中画
├─ Translation/
│  ├─ AudioTapProcessor.swift     # MTAudioProcessingTap 抓 PCM
│  ├─ SpeechRecognizerService.swift # 流式识别 + 45s 续接
│  ├─ Translator.swift            # 端上翻译 + 在线兜底
│  └─ LiveCaptionEngine.swift     # 断言成句、节流、字幕行管理
└─ Views/
   ├─ HomeView / SearchView / LibraryView / VideoCard
   └─ Player/
      ├─ PlayerScreen.swift       # 页面组合、全屏、字幕层、回调
      ├─ PlayerControls.swift     # 自绘控制面板
      ├─ PlayerGestureLayer.swift # 手势 + HUD + 亮度/音量
      ├─ PlayerSurface.swift      # AVPlayerLayer 宿主
      └─ OrientationSupport.swift # 方向锁 + TabBar 显隐
```

## 六、打包成 IPA

### 方式 A：GitHub Actions（无需 Mac）

1. 仓库 → **Actions** → **Build IPA** → **Run workflow**
2. 等 3~6 分钟
3. 运行页面底部 **Artifacts → KanAV-unsigned-ipa**，解压得到 `KanAV-unsigned.ipa`

推 tag（如 `v1.0.7`）会自动把 IPA 挂到 Release 附件。

### 方式 B：本地 macOS

```bash
brew install xcodegen
bash tools/build_ipa.sh
```

## 七、装到 iPhone

未签名 IPA 要用自己的 Apple ID 现场签名：

| 工具 | 平台 | 说明 |
| --- | --- | --- |
| Sideloadly | Windows / macOS | 连数据线 → 拖入 ipa → 填 Apple ID → Start |
| AltStore / SideStore | Windows / macOS | 装一次后可 WiFi 续签 |
| 爱思助手 | Windows | 「IPA 签名」→ 签名后安装 |
| TrollStore | 特定 iOS 版本 | 支持范围内可永久安装 |

免费 Apple ID 签名 **7 天**有效，到期重签即可，观看记录不丢。
首次打开提示不受信任：设置 → 通用 → VPN与设备管理 → 信任你的 Apple ID。

## 八、常见问题

**Q：提示「解析不出播放地址」？**
个别片源的 `player_aaaa.encrypt` 用了别的编码。抓下播放页 HTML 看 `player_aaaa`，在 `Parser.playSource` 补一个分支。

**Q：全屏没旋转？**
iPhone 上全屏按钮会强制横屏（`requestGeometryUpdate`）。如果系统开了「方向锁定」，先在控制中心关掉。

**Q：实时字幕一直「准备中」？**
先确认系统的语音识别语言包已下载；再确认 设置 → KanAV → 语音识别 已允许。低版本 iOS 还需要在 `Translator` 里配在线接口。

**Q：想换站点 / 改分类？**
`Core/Models.swift` 顶部：`Site.base`、`Site.categories`。

**Q：改 App 名 / Bundle ID / 图标？**
`project.yml` 里 `CFBundleDisplayName`、`PRODUCT_BUNDLE_IDENTIFIER`；图标替换 `Assets.xcassets/AppIcon.appiconset/`，或改 `tools/make_icons.ps1` 后重跑。

---

本项目是第三方客户端，只做数据解析、播放外壳与端上字幕，不存储、不转码、不分发任何媒体内容。
