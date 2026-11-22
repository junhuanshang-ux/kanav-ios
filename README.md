# 博客 · 原生 iOS 客户端

站点 [kanav.ad](https://kanav.ad) 的**纯原生** SwiftUI 客户端，外壳看起来是个播客类 App（名字叫「博客」，图标是紫色波纹），内核是完整的视频客户端。

- 目标：iPhone / iPad，iOS 15.0+
- 产物：`KanAV-unsigned.ipa`（未签名，自签安装）
- 构建：GitHub Actions 云端 macOS，约 10~15 分钟（含 whisper.cpp 编译）

---

## 一、数据怎么来的

站点没有开放 JSON 接口（`/api.php/provide/vod` 返回 `closed`，`/index.php/api/vod` 404），
所以列表与搜索走 HTML 解析；播放地址可解：

```
player_aaaa.url  --base64-->  %68%74%74%70%73...  --url decode-->  https://cdn14.11yun.space/xxx.m3u8
```

解析出来就是标准 HLS 直链，无 DRM、无需 Referer。规则集中在 `Parser.swift`。

## 二、功能

| 模块 | 说明 |
| --- | --- |
| 发现 | 14 个分类横向切换，双列网格，触底自动翻页，封面懒加载 |
| 搜索 | 番号 / 片名 / 演员关键词 |
| 我的 | 最近观看（本地 60 条）+ 安全设置 + whisper 模型管理 |

## 三、播放器

`AVPlayerViewController` 的控件改不了，整条链路是 `AVPlayerLayer` + 自绘 SwiftUI 控件层。

| 能力 | 实现 |
| --- | --- |
| HLS / MP4 | `AVURLAsset` + `AVPlayerItem`，m3u8 与 mp4 统一 |
| 缓冲监听 | KVO `isPlaybackLikelyToKeepUp` / `bufferEmpty` + `PlaybackStalled` 通知，七态状态机 |
| 加载动画 | 中央菊花 + 底部「缓冲中」角标 |
| 错误提示 | `item.error` → 中文提示 + 重试 / 返回 |
| 进度条 | 自绘双层：半透明白=已缓冲，红=已播放，白点可拖带预览 |
| 时间 / ±15s | 等宽数字，小时位自动出现 |
| 手势 | 横滑 seek（整屏=120 秒）、左半屏亮度、右半屏音量、单击显隐面板 |
| 倍速 / 比例 / 循环 | 0.5~2×；适应/填充/拉伸；循环播放 |
| 音轨 / 内嵌字幕 | `AVMediaSelectionGroup`（`.audible` / `.legible`） |
| 画中画 | `AVPictureInPictureController(playerLayer:)` |
| 全屏 | 强制横屏（`requestGeometryUpdate`），可退回内嵌 |
| 返回 | 面板 4 秒自动隐藏后，**左上角常驻圆形返回键** |
| 状态回调 | `PlayerScreen(onStateChange:onProgress:)` |

> 早期版本点屏幕会出现画面「忽大忽小」：`withAnimation` 让 SwiftUI 对 `AVPlayerLayer` 做了尺寸插值。
> 现在给 `PlayerSurface` 加了 `transaction.disablesAnimations`，控制层改用 `opacity`，所有浮层走 `overlay`，播放层布局完全不受显隐影响。

## 四、实时字幕（Whisper.cpp 本地推理）

```
AVPlayerItem.audioMix
  └─ MTAudioProcessingTap（PostEffects，拿解码 PCM，不额外起播放）
       └─ AudioResampler（→ 16kHz 单声道 Float32）
            └─ whisper.cpp  whisper_full()（Metal + CoreML 加速）
                 └─ Translation（iOS 18+ 端上翻译）或自建在线接口
                      └─ 双语字幕层
```

- 模型：`ggml-base-q5_1.bin`（约 57 MB），首次在「我的 → 实时字幕」下载，之后离线可用
- 切分：4 秒一段送入推理，串行队列，音频线程只做入队，不阻塞播放
- 兜底：模型缺失或构建未含 whisper 时，自动回退系统 `SFSpeechRecognizer`
- 编译：CI 现场 `BUILD_STATIC_XCFRAMEWORK=ON ./build-xcframework.sh`，取 `build-ios-device` 的静态 framework 链进主二进制；whisper 编进了 CoreML 编码器，所以额外链接 `CoreML / Accelerate / Metal / libc++`

## 五、面容锁

- `LAContext` 生物识别：启动 App、从后台回到前台自动上锁
- 开关在「我的 → 安全」，没有 Face ID 的设备自动退回密码验证
- 验证期间不重复触发，取消不报错

## 六、代码结构

```
KanAV/Sources/
├─ KanAVApp.swift                 # 入口 + Tab + 锁屏覆盖
├─ Core/
│  ├─ Models.swift  Net.swift  Parser.swift  HistoryStore.swift
│  └─ AppLock.swift               # 面容 / 触控 ID 锁
├─ Playback/
│  ├─ PlayerEngine.swift          # 状态机 / 缓冲 / 倍速 / 循环 / 轨道 / 音频管线
│  └─ PiPManager.swift
├─ Translation/
│  ├─ AudioTapProcessor.swift     # MTAudioProcessingTap
│  ├─ AudioResampler.swift        # → 16kHz mono
│  ├─ WhisperEngine.swift         # whisper.cpp C API 封装
│  ├─ WhisperModelStore.swift     # 模型下载 / 删除
│  ├─ SpeechRecognizerService.swift # 系统识别兜底
│  ├─ Translator.swift            # 端上翻译 + 在线兜底
│  └─ LiveCaptionEngine.swift     # 编排：Whisper 优先，Speech 兜底
└─ Views/
   ├─ HomeView / SearchView / LibraryView / VideoCard
   └─ Player/
      ├─ PlayerScreen.swift  PlayerControls.swift  PlayerGestureLayer.swift
      ├─ PlayerSurface.swift  OrientationSupport.swift
```

## 七、打包成 IPA

GitHub Actions：**Actions → Build IPA → Run workflow**，完成后在运行页底部 **Artifacts → KanAV-unsigned-ipa** 下载。
推 `v*` tag 会自动把 IPA 挂到 Release。

本地 macOS：`brew install xcodegen && bash tools/build_ipa.sh`（本地没有 whisper framework 时自动回退系统识别）。

## 八、装到 iPhone

Sideloadly / AltStore / 爱思助手 自签安装；免费 Apple ID 签名 7 天有效。
首次打开提示不受信任：设置 → 通用 → VPN与设备管理 → 信任。

## 九、常见问题

**Q：实时字幕一直提示「Whisper 模型未下载」？**
去「我的 → 实时字幕」点下载（约 57 MB）。下载完再开关一次字幕。

**Q：字幕出得慢 / 断续？**
base-q5_1 在 A14 以上约 0.5~1× 实时，4 秒切片意味着延迟 2~6 秒；这类片源旁白少、环境音多，识别本身就会断。

**Q：全屏没旋转？**
检查系统是否开了方向锁定；App 内全屏按钮走 `requestGeometryUpdate` 强制横屏。

**Q：改名字 / Bundle ID / 图标？**
`project.yml` 的 `CFBundleDisplayName`、`PRODUCT_BUNDLE_IDENTIFIER`；图标改 `tools/make_icons.ps1` 后重跑。

---

第三方客户端，只做数据解析、播放外壳与本地字幕，不存储、不转码、不分发任何媒体内容。
