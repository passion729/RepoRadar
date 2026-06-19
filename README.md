# RepoRadar

一个用 SwiftUI 写的 macOS 桌面 App,相当于 GitHub 的本地"仓库雷达":

- **汇总「与我相关的 PR」**:跨所有仓库列出你创建、被指派、被请求 review、被提到的 open PR,按仓库分组,每条标明关系
- **汇总通知**:拉取你账号下的全部 GitHub 通知,按仓库分组,新未读项以系统通知(Banner)推送
- 添加要监控的 GitHub 仓库(`owner/name` 或仓库链接),按仓库查看其打开中的 Pull Request
- 既能看汇总,也能下钻到单个仓库;点击任意条目直达浏览器
- Dock 图标 + 菜单栏常驻入口,菜单栏弹窗可快速一览
- 用 Swift Package Manager 构建,**不依赖 Xcode IDE**

## 环境要求

- macOS 14 (Sonoma) 或更新
- Swift 工具链(装 Xcode Command Line Tools 即可:`xcode-select --install`)

## 构建并运行

```bash
cd RepoRadar
chmod +x build.sh
./build.sh            # debug 构建并打包成 RepoRadar.app
open RepoRadar.app
```

发布版:`./build.sh release`。

开发期只想快速看是否编译通过,可以直接 `swift build`。

## 首次使用

1. 启动后,菜单栏会出现雷达图标,Dock 也有图标、并弹出主窗口。
2. 打开 **设置(⌘,)**,选一种方式认证:
   - **用 GitHub 登录(推荐)**:点按钮,会显示一个设备码并打开 GitHub 页面,
     在浏览器里输入该码授权即可,App 会自动完成登录。
   - **粘贴 Personal Access Token**:在 https://github.com/settings/tokens 创建,勾选
     `repo` 和 `notifications` 权限,粘贴后点保存。
   - 两种方式拿到的 token 都保存在 macOS 钥匙串,不会明文落盘。
3. 主窗口点左上角 **+** 添加仓库,例如 `apple/swift`。
4. 应用默认每 5 分钟自动刷新一次(可在设置里按分钟自定义,最小 1 分钟),也可用 ⌘R / 刷新按钮手动刷新。

> 界面默认 **English (US)**,可在 **设置 → Language / 语言** 里切换为简体中文,
> 即时生效、无需重启。

## 配置 OAuth(用 GitHub 登录)

"用 GitHub 登录"用的是 GitHub 的 **OAuth Device Flow**:App 显示一个设备码,你在
浏览器里输入授权,App 后台轮询拿到 token。**不需要 client secret、不需要回调地址**,
代码里只放一个公开的 `client_id`(见 `Services/GitHubOAuth.swift`)。

如果你要用自己的 OAuth App:在 https://github.com/settings/developers → **OAuth Apps**
→ **New OAuth App** 注册,进入该 App 设置勾选 **Enable Device Flow**,然后把
`client_id` 替换到 `GitHubOAuthConfig` 里即可(callback URL 随便填、用不到)。

## 代码结构

```
Sources/RepoRadar/
├── RepoRadarApp.swift        # @main:Window + MenuBarExtra + Settings 三个 Scene
├── Models/
│   ├── Repository.swift      # owner/name,支持从链接解析
│   ├── PullRequest.swift     # GitHub pulls API 映射
│   └── GitHubNotification.swift
├── Services/
│   ├── KeychainStore.swift   # Token 钥匙串读写
│   ├── Localization.swift    # 原生本地化(.lproj/.strings)+ 实时语言切换(Localizer)
│   ├── FontTheme.swift       # 字体设置:已安装字体枚举 + UI/mono 字号磅值
│   ├── GitHubOAuth.swift     # OAuth Device Flow 登录(设备码)
│   ├── GitHubClient.swift    # async/await REST 客户端(actor)
│   └── AppState.swift        # ObservableObject 中枢:持久化、刷新、系统通知
├── Resources/
│   ├── en.lproj/Localizable.strings        # 英文文案(默认)
│   └── zh-Hans.lproj/Localizable.strings   # 简体中文文案
└── Views/
    ├── MainWindowView.swift      # NavigationSplitView 侧栏 + 详情
    ├── MyPullRequestsView.swift  # 汇总:与我相关的所有 PR(按仓库分组)
    ├── MenuBarContentView.swift  # 菜单栏弹窗
    ├── PullRequestListView.swift / PullRequestRow.swift
    ├── NotificationListView.swift / NotificationRow.swift
    ├── AddRepositoryView.swift
    └── SettingsView.swift
```

## 已知边界 / 可扩展点

- 未签名/临时签名(ad-hoc)的 App,系统通知与钥匙串在个别 macOS 版本上可能需要
  正式签名才完全稳定;build.sh 已做 ad-hoc 签名以尽量规避。
- 当前只读 PR 列表与通知。可以继续加:把通知标记为已读
  (`PATCH /notifications/threads/{id}`)、PR 的 review 状态、Issues、CI 检查等。
- 想加应用图标:放一个 `.icns` 到 `Contents/Resources/`,并在 Info.plist 里加
  `CFBundleIconFile`。
