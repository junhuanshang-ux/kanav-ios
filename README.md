# KanAV · 原生 iOS 客户端

站点 [kanav.ad](https://kanav.ad) 的**纯原生** SwiftUI 客户端：不带 WebView，不套壳网页。
列表、搜索、播放全部走原生控件，视频交给 `AVPlayer` 直接播 HLS。

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

解析出来的就是标准 HLS 直链，无 DRM、无需 Referer，`AVPlayer` 原生播放，支持全屏、AirPlay、画中画。
解析规则全部集中在 `Parser.swift`，站点换模板只改这一个文件。

## 二、功能

| 模块 | 说明 |
| --- | --- |
| 发现 | 14 个分类横向切换（最新/中文字幕/日韩有码/日韩无码/国产/自拍/泄密/探花/主播/动漫/里番/Motion/3D/同人） |
| 列表 | 双列网格，触底自动翻页，封面懒加载，右下角显示时长 |
| 搜索 | 番号 / 片名 / 演员关键词，直接解析站点搜索结果页 |
| 播放 | 点卡片即进播放页，自动解析 m3u8 并起播，支持全屏、锁屏常亮 |
| 最近观看 | 本地记录最近 60 条，可单条移除或清空 |
| 容错 | 网络失败有重试、解析失败有明确提示，不会白屏 |

## 三、代码结构

```
KanAV/
├─ Sources/
│  ├─ KanAVApp.swift          # App 入口 + 三个 Tab + 配色
│  ├─ Core/
│  │  ├─ Models.swift         # 站点常量、分类、VideoItem
│  │  ├─ Net.swift            # URLSession 封装（UA / Referer / 超时）
│  │  ├─ Parser.swift         # HTML 卡片解析 + player_aaaa 解密 + 实体解码
│  │  └─ HistoryStore.swift   # 最近观看（UserDefaults）
│  └─ Views/
│     ├─ HomeView.swift       # 分类栏 + 无限滚动网格 + FeedViewModel
│     ├─ VideoCard.swift      # 封面卡片 / 列表行
│     ├─ SearchView.swift     # 搜索
│     ├─ PlayerScreen.swift   # AVPlayerViewController 包装
│     └─ LibraryView.swift    # 最近观看
├─ Resources/Assets.xcassets  # AppIcon（18 个尺寸，脚本生成）
└─ Info.plist                  # 由 xcodegen 依 project.yml 生成
```

## 四、打包成 IPA

### 方式 A：GitHub Actions（无需 Mac）

仓库已配置好 [.github/workflows/build-ipa.yml](.github/workflows/build-ipa.yml)：

1. 仓库 → **Actions** → **Build IPA** → **Run workflow**
2. 等 3~6 分钟
3. 该次运行页面底部 **Artifacts → KanAV-unsigned-ipa**，解压得到 `KanAV-unsigned.ipa`

推 tag（如 `v1.0.2`）会自动把 IPA 挂到 Release 附件。

### 方式 B：本地 macOS

```bash
brew install xcodegen
bash tools/build_ipa.sh
```

## 五、装到 iPhone

未签名 IPA 需要用自己的 Apple ID 现场签名：

| 工具 | 平台 | 说明 |
| --- | --- | --- |
| Sideloadly | Windows / macOS | 连数据线 → 拖入 ipa → 填 Apple ID → Start |
| AltStore / SideStore | Windows / macOS | 装一次后可 WiFi 续签 |
| 爱思助手 | Windows | 「IPA 签名」→ 签名后安装 |
| TrollStore | 特定 iOS 版本 | 支持范围内可永久安装 |

免费 Apple ID 签名 **7 天**有效，到期重签即可，观看记录不丢。
首次打开提示不受信任：设置 → 通用 → VPN与设备管理 → 信任你的 Apple ID。

## 六、常见问题

**Q：列表一直转圈 / 提示服务器返回 403？**
站点挂在 Cloudflare 后面，偶尔对裸 IP 限速。App 已带 Safari UA 和 Referer，重试一般能过；长期不行就换 `Site.base` 到备用域 `https://kanav.fun`。

**Q：某条能点开但提示「解析不出播放地址」？**
站点个别片源的 `player_aaaa.encrypt` 用了其它编码。把播放页 HTML 抓下来看 `player_aaaa`，在 `Parser.playSource` 里补一个分支即可。

**Q：播放黑屏但有声音？**
HLS 分片域名偶发抽风，退出重进即可；播放器支持全屏、AirPlay 和画中画。

**Q：想改站点 / 改分类？**
`Core/Models.swift` 顶部：`Site.base`、`Site.categories`。

**Q：改 App 名 / Bundle ID / 图标？**
`project.yml` 里 `CFBundleDisplayName`、`PRODUCT_BUNDLE_IDENTIFIER`；图标替换 `Assets.xcassets/AppIcon.appiconset/`，或改 `tools/make_icons.ps1` 后重跑。

---

本项目是第三方客户端，只做数据解析与播放外壳，不存储、不转码、不分发任何媒体内容。
