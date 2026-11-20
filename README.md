# KanAV iOS 壳工程（网页 → 原生 App → 未签名 IPA）

把 [`https://kanav.ad/`](https://kanav.ad/) 封装成一个真正能装进 iPhone 的 App：
原生 `WKWebView` 壳 + 底部工具栏 + 下拉刷新 + 全屏播放，然后在 **GitHub Actions 的云端 macOS 机器**上编译并打包成 `.ipa`，本地不需要任何 Mac。

- 目标机型：iPhone / iPad，iOS 15.0 及以上
- 产物：`KanAV-unsigned.ipa`（未签名，需自签后安装）
- 每次构建耗时约 3~6 分钟

---

## 一、目录结构

```
kanav-ios/
├─ project.yml                        # XcodeGen 工程描述（真正的工程由它生成）
├─ KanAV/
│  ├─ Sources/
│  │  ├─ AppDelegate.swift            # 启动 + 音频会话（静音开关也能出声）
│  │  ├─ SceneDelegate.swift          # 深色导航栏/工具栏、窗口装配
│  │  └─ WebViewController.swift      # 核心：WKWebView 壳、广告拦截、全屏播放
│  ├─ Resources/
│  │  └─ Assets.xcassets/             # AppIcon（已生成 18 个尺寸）+ 配色
│  └─ Info.plist                       # 由 xcodegen 依据 project.yml 生成
├─ tools/make_icons.ps1               # 重新生成图标的脚本（Windows 可跑）
└─ .github/workflows/build-ipa.yml    # GitHub Actions：编译 + 打包 IPA
```

---

## 二、已实现的特性

| 能力 | 实现方式 |
| --- | --- |
| 整站加载 | `WKWebView` + 伪装成 iOS Safari 的 UA（避免被识别成精简版） |
| 底部工具栏 | 后退 / 前进 / 首页 / 刷新（加载中变停止） |
| 顶部进度条 | KVO 监听 `estimatedProgress` |
| 下拉刷新 | `UIRefreshControl` |
| 左右滑动前进后退 | `allowsBackForwardNavigationGestures` |
| 视频全屏 | `allowsInlineMediaPlayback` + `isElementFullscreenEnabled` + 全方向支持 |
| 后台/PiP 播放 | `UIBackgroundModes: audio` + `AVAudioSession.playback` |
| 广告拦截 | 自动弹窗（无手势的 `window.open`）静默丢弃；用户主动点击的站外链接交给系统浏览器 |
| 登录态保留 | `WKWebsiteDataStore.default()` 持久化 Cookie |
| 原生弹窗 | `alert / confirm / prompt` 用 `UIAlertController` 接管 |
| 网页下载 | `.m3u8/.mp4/zip` 等非可渲染响应交给系统处理 |
| 加载失败 | 内置错误页 + 一键重试（不再白屏） |
| 深色外观 | 导航栏/工具栏深色 + `overrideUserInterfaceStyle = .dark` |

想换成别的站点，只改 `WebViewController.swift` 顶部的 `Site` 枚举：

```swift
private enum Site {
    static let home = "https://kanav.ad/"
    static let trustedHostSuffixes = ["kanav.ad", "kanav.fun"]
    static let displayName = "KanAV"
    static let accent = UIColor(red: 1.0, green: 0.18, blue: 0.33, alpha: 1)
}
```

---

## 三、上传到 GitHub（网页操作，不用装任何工具）

### 1. 解压

把得到的 `kanav-ios.zip` 解压到一个文件夹，里面应该能直接看到 `project.yml`、`KanAV`、`.github` 这些内容。

> `.github` 是隐藏文件夹：Windows 资源管理器 →「查看」→ 勾选「隐藏的项目」才看得到。

### 2. 新建仓库

GitHub → 右上角 `+` → **New repository**：

- Repository name：`kanav-ios`
- 可见性：**Public**（Actions 分钟数完全免费；选 Private 也可以，每月有 2000 分钟免费额度，macOS runner 按 10 倍计费）
- 不要勾选 "Add a README file"

### 3. 上传全部文件

进入空仓库 → **Add file** → **Upload files**：

1. 打开解压后的 `kanav-ios` 文件夹，`Ctrl+A` 全选（包含 `.github`、`KanAV`、`tools`、`project.yml`、`README.md`、`.gitignore`）
2. 直接拖进网页的上传区域
3. 底部 Commit message 随便写，例如 `init`，点 **Commit changes**

> 如果浏览器把 `.github` 吞掉了（个别浏览器不支持拖隐藏目录），改用：
> **Add file → Create new file** → 文件名填 `.github/workflows/build-ipa.yml` → 把本仓库里同名文件的内容整段粘进去 → Commit。

### 4. 确认工作流存在

仓库页面 → **Actions** 标签页，左侧应能看到 **Build IPA**。
如果提示 "Workflows aren't being run on this repository"，点一次 **I understand my workflows, go ahead and enable them**。

---

## 四、打包出 IPA

### 方式 A：手动触发（最常用）

1. **Actions** → 左侧 **Build IPA** → 右侧 **Run workflow** → **Run workflow**
2. 等 3~6 分钟，绿勾出现
3. 点进这次运行 → 页面底部 **Artifacts** → 下载 `KanAV-unsigned-ipa`
4. 下载到的是个 zip，解压后得到：
   - `KanAV-unsigned.ipa` ← 这就是要装到手机上的包
   - `checksum.txt`（SHA-256）
   - `build.log`（编译日志，出问题看它）

### 方式 B：打 tag 自动发 Release

在仓库 **Releases → Draft a new release** 里填 tag `v1.0.1` 并发布（或本地 `git tag v1.0.1 && git push --tags`），
Actions 会编译并把 IPA 直接挂到该 Release 的附件里，方便长期保存和分享链接。

---

## 五、装到 iPhone 上

**未签名 IPA 不能直接双击安装**，需要用自己的 Apple ID 现场签名（免费账号即可）。任选一种：

| 工具 | 平台 | 说明 |
| --- | --- | --- |
| **Sideloadly** | Windows / macOS | 最省事：连数据线 → 拖入 ipa → 填 Apple ID → Start，自动签名安装 |
| **AltStore / SideStore** | Windows / macOS | 装一次客户端后可 WiFi 续签，需每 7 天刷新 |
| **爱思助手** | Windows | 「IPA 签名」→ 用 Apple ID 签名后安装 |
| **TrollStore** | 仅特定 iOS 版本 | iOS 14.0–16.6.1 / 17.0 等支持范围内可永久安装，无需签名 |

免费 Apple ID 的限制：**签名 7 天有效**，一台设备最多 3 个自签 App；到期重签一次即可（登录态不丢）。
付费开发者账号（$99/年）签名为 1 年。

首次启动如果提示「不受信任的开发者」：

> 设置 → 通用 → VPN与设备管理 → 开发者 App → 选择你的 Apple ID → 信任

---

## 六、常见问题

**Q：构建报 `No such file or directory: KanAV.xcodeproj`？**
A：`xcodegen generate` 这步失败了。绝大多数情况是 `project.yml` 没上传成功或缩进被改坏，重新上传一次。

**Q：构建失败了怎么排查？**
A：运行页面底部的 **Artifacts → build-log** 里有完整编译日志；本工程在失败时也会自动上传 `build.log`。

**Q：构建报 `Unable to find a destination matching...`？**
A：workflow 里已经固定 `-destination 'generic/platform=iOS'`，若仍出现，看 `build.log` 里 `xcodebuild -version` 是否正常。

**Q：App 打开白屏 / 一直转圈？**
A：站点在 Cloudflare 后面时首次可能被挑战（人机验证），App 内会自动跟随；如果站点临时挂了，错误页会显示原因和重试按钮。也可以换 `Site.home` 为备用域名 `https://m1.kanav.fun/`。

**Q：视频点全屏没反应？**
A：iPhone 上需要 App 支持横屏（已开）。若站点播放器自己锁了 `playsinline`，全屏由它内部的按钮控制，属于网页行为。

**Q：想在 Mac 上本地编译？**
```bash
brew install xcodegen
xcodegen generate
open KanAV.xcodeproj   # 真机运行需在 Signing & Capabilities 里选自己的 Team
```

**Q：想改 App 名字 / 图标 / Bundle ID？**

- 名字：`project.yml` 里 `CFBundleDisplayName`
- Bundle ID：`project.yml` 里 `PRODUCT_BUNDLE_IDENTIFIER`（自签时最好改成 `com.你的名字.kanav`，避免和别人的签名冲突）
- 图标：替换 `KanAV/Resources/Assets.xcassets/AppIcon.appiconset/` 里的 PNG（或改 `tools/make_icons.ps1` 后重跑）

---

## 七、免责声明

本项目只是一个 WebView 容器，不修改、不代理、不缓存站点内容；页面内容、版权与合规责任均由站点运营方承担。
仅供个人学习和自用设备安装，请遵守所在地法律法规。
