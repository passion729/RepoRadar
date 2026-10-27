// Every string on the page, in both languages. `{v}` placeholders are filled in by the page;
// in body text `**bold**`, `` `code` `` and `[key]` (a keycap) are rendered by `rich()` in Landing.
// The demo windows stay in English in both: they mirror the app, whose interface is English-only.

const en = {
  lang: "en",
  meta: {
    title: "RepoRadar — the GitHub dashboard GitHub never built",
    description: "PRs, CI and notifications on one screen on your Mac. No more jumping between GitHub tabs.",
  },
  nav: {
    features: "Features",
    keyboard: "Keyboard",
    privacy: "Privacy",
    start: "Download",
    github: "GitHub",
    other: "中文",
    otherHref: "/zh/",
    otherLang: "zh-CN",
  },
  hero: {
    eyebrow: "Native for macOS",
    title: "The GitHub dashboard GitHub never built.",
    lede: "PRs, CI and notifications on one screen. No more jumping between GitHub tabs.",
    download: "Download for Mac",
    see: "See how it works",
    meta: "v{version} · macOS 26 · Apple silicon",
    demoLabel: "Try RepoRadar's Now screen: J and K move, A approves, R re-runs, E marks done, Command-Z undoes",
    hintKeys: "Click the window, then [J] [K] to move, [A] approve, [R] re-run, [E] done, [⌘Z] undo.",
    hintTouch: "Tap a row to act on it.",
    demoNote: "",
  },
  pillars: [
    { eyebrow: "One screen", title: "Everything in one place", body: "PRs, CI runs, deploys and mentions, ranked by what needs you first." },
    { eyebrow: "Act in place", title: "No tab to open", body: "Approve, re-run, merge and reply with one key." },
    { eyebrow: "Straight to the error", title: "Failures first", body: "When CI fails, the log opens on the failing line." },
  ],
  pulls: {
    eyebrow: "Pull requests",
    title: "See where a PR is stuck.",
    lede: "Checks, reviews and merge state in one bar. The step that's blocking lights up.",
  },
  actions: {
    eyebrow: "Actions",
    title: "CI failed? Two clicks to the error.",
    lede: "A job graph, the failing tests on top, and re-run right there.",
  },
  inbox: {
    eyebrow: "Inbox",
    title: "Reply without opening GitHub.",
    body: "The whole thread is here. Read it and answer it.",
  },
  menu: {
    eyebrow: "Menu bar",
    title: "Urgent things, from the menu bar.",
    body: "The icon turns red when your push breaks. Re-run it from there.",
  },
  keys: {
    eyebrow: "Keyboard first",
    title: "Clear it all from the keyboard.",
    lede: "Every list has single-key shortcuts.",
    press: " Try one.",
    labels: ["Move up and down", "Done", "Approve", "Re-run failed jobs", "Merge", "Jump anywhere", "Undo", "Send reply"],
  },
  trust: {
    eyebrow: "Privacy",
    title: "It only talks to GitHub.",
    items: [
      ["No password", "Sign in with the device flow or a personal access token."],
      ["In your Keychain", "Your token is kept by macOS."],
      ["Light on your quota", "ETags, so unchanged data doesn't count."],
      ["Native", "SwiftUI and Liquid Glass."],
    ],
  },
  start: {
    title: "Get RepoRadar.",
    lede: "Download the DMG, or build it from source.",
    tabsLabel: "Ways to get RepoRadar",
    downloadTab: "Download",
    downloadButton: "Download RepoRadar {version}",
    downloadMeta: "DMG · {size} · Apple silicon · released {date}",
    gatekeeper: "RepoRadar isn't notarized, so macOS blocks the first launch. Click **Open Anyway** in System Settings → Privacy & Security, or run:",
    after: "It updates itself after that.",
    buildTab: "Build from source",
    buildNote: "Needs a Swift 6 toolchain.",
    github: "See the source on GitHub",
    copy: "Copy",
    copied: "Copied",
    copyLabel: "Copy commands",
  },
  footer: {
    tagline: "The GitHub dashboard for your Mac · v{version}",
    releases: "Releases",
  },
};

export type Content = typeof en;

// Written the way Chinese developers talk: PR, Review, CI, Job stay as they are.
const zh: Content = {
  lang: "zh-CN",
  meta: {
    title: "RepoRadar：GitHub 一直没做的 Dashboard",
    description: "PR、CI、通知一屏看全，不用在 GitHub 页面间来回跳。",
  },
  nav: {
    features: "功能",
    keyboard: "快捷键",
    privacy: "隐私",
    start: "下载",
    github: "GitHub",
    other: "English",
    otherHref: "/",
    otherLang: "en",
  },
  hero: {
    eyebrow: "原生 macOS 应用",
    title: "GitHub 一直没做的 Dashboard。",
    lede: "PR、CI、通知一屏看全，不用在 GitHub 页面间来回跳。",
    download: "下载 Mac 版",
    see: "看看怎么用",
    meta: "v{version} · macOS 26 · Apple 芯片",
    demoLabel: "试用 RepoRadar 的 Now 页面：J、K 上下切换，A 批准，R 重跑，E 处理完，Command-Z 撤销",
    hintKeys: "点一下窗口，用 [J] [K] 上下切换，[A] 批准，[R] 重跑，[E] 处理完，[⌘Z] 撤销。",
    hintTouch: "点开一行，直接操作。",
    demoNote: "App 界面目前只有英文。",
  },
  pillars: [
    { eyebrow: "一屏看全", title: "不用来回跳", body: "PR、CI、部署、@ 你的消息，按紧急程度排好。" },
    { eyebrow: "就地处理", title: "不用开网页", body: "批准、重跑、合并、回复，按一个键就行。" },
    { eyebrow: "直达报错", title: "先看哪里挂了", body: "CI 失败时，日志直接停在报错那一行。" },
  ],
  pulls: {
    eyebrow: "Pull Request",
    title: "这个 PR 卡在哪，一眼就知道。",
    lede: "检查、Review、合并状态排成一行，卡住的那步会高亮。",
  },
  actions: {
    eyebrow: "Actions",
    title: "CI 挂了？点两下，直达报错。",
    lede: "Job 依赖图，失败的测试置顶，原地重跑。",
  },
  inbox: {
    eyebrow: "收件箱",
    title: "不开网页，直接回复。",
    body: "完整的讨论都在这里，看完就能回。",
  },
  menu: {
    eyebrow: "菜单栏",
    title: "急事，菜单栏就能处理。",
    body: "推送一挂图标就变红，点开就能重跑。",
  },
  keys: {
    eyebrow: "全键盘操作",
    title: "手不离键盘，清空待办。",
    lede: "每个列表都支持单键快捷键。",
    press: "按一下试试。",
    labels: ["上下切换", "处理完", "批准", "重跑失败的 Job", "合并", "跳转到任意位置", "撤销", "发送回复"],
  },
  trust: {
    eyebrow: "隐私",
    title: "只和 GitHub 通信。",
    items: [
      ["不用密码", "设备授权或个人访问令牌登录。"],
      ["钥匙串保管", "令牌存在 macOS 钥匙串里。"],
      ["省 API 额度", "带 ETag，数据没变就不占额度。"],
      ["原生体验", "SwiftUI + Liquid Glass。"],
    ],
  },
  start: {
    title: "装上试试。",
    lede: "下载 DMG，或者从源码构建。",
    tabsLabel: "获取 RepoRadar 的方式",
    downloadTab: "下载",
    downloadButton: "下载 RepoRadar {version}",
    downloadMeta: "DMG · {size} · Apple 芯片 · {date} 发布",
    gatekeeper: "没有经过 Apple 公证，首次打开会被拦截。到“系统设置 → 隐私与安全性”点 **仍要打开**，或者运行：",
    after: "之后会自动更新。",
    buildTab: "从源码构建",
    buildNote: "需要 Swift 6 工具链。",
    github: "去 GitHub 看源码",
    copy: "复制",
    copied: "已复制",
    copyLabel: "复制命令",
  },
  footer: {
    tagline: "Mac 上的 GitHub Dashboard · v{version}",
    releases: "版本发布",
  },
};

export const content = { en, zh };

export function fill(template: string, values: Record<string, string>) {
  return template.replace(/\{(\w+)\}/g, (_, key: string) => values[key] ?? "");
}
