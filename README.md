# RepoRadar

A native macOS app that brings your GitHub notifications, pull requests and GitHub Actions runs together in one window, across every repository you work on.

Built with SwiftUI and Liquid Glass for macOS 26, packaged with Swift Package Manager. No Xcode project needed.

## Features

**Inbox**
- All your GitHub notifications, filtered by Unread, All, Review Requests or CI Activity
- Mark threads as read or done per row, from the toolbar, the context menu, or with Mail's shortcuts (⇧⌘U, ⌃⌘A)
- Opening a thread marks it read. The inbox is polled every minute using ETags, so unchanged checks don't count against your rate limit
- Selecting a CI notification finds the workflow run it refers to and shows its full details

**Pull Requests**
- Open pull requests across all repositories, filtered by Review Requested, Authored, Assigned or Mentioned
- Details: branches, diff size, reviewers, labels, the rendered markdown description, comments, and the Actions checks for the head commit

**Actions**
- The latest run of every workflow in every repository you own, collaborate on or belong to through an organization, filtered by Failing, Running or Passing
- A per-repository run history in the sidebar
- A workflow graph like GitHub's: jobs laid out by `needs:`, parallel jobs grouped, redundant edges hidden. Pan by dragging or with a two-finger swipe, zoom with the mouse wheel or a pinch, and Fit to see everything
- Jobs and steps for every run, with the failing job selected automatically
- Re-run failed jobs, re-run all jobs, or cancel a run (with confirmation)

**Everywhere**
- A dense, sortable table layout with a resizable detail pane below or beside it
- Search by field (⌘F) and a sidebar filter (⇧⌘F)
- Menu bar extra with unread notifications, review requests and failing workflows
- System notifications for new GitHub notifications and newly failing workflows. The Dock badge shows unread plus failing
- A status bar showing your remaining API quota
- Custom font, monospaced font and text size (Settings → Appearance)

## Requirements

- macOS 26 or later
- A Swift 6 toolchain (Xcode or the Command Line Tools)

## Build and run

```bash
git clone https://github.com/passion729/RepoRadar.git
cd RepoRadar
./build.sh            # builds and bundles RepoRadar.app (./build.sh release for an optimized build)
open RepoRadar.app
./test.sh             # runs the test suite
```

`build.sh` signs the app ad hoc so the Keychain and notifications work without a developer account.

## Signing in

Open **Settings (⌘,) → Account** and either:

- **Sign in with GitHub**: uses the OAuth device flow. The code is copied for you and github.com opens to approve it. No password or client secret is involved.
- **Paste a personal access token** with the `repo` and `notifications` scopes.

The token is stored in the macOS Keychain. Debug builds also read `REPORADAR_TOKEN` or `~/.reporadar-dev-token`, so rebuilding doesn't trigger Keychain prompts.

To use your own OAuth App, enable **Device Flow** in its settings and replace `DeviceFlow.clientID` in `Sources/RepoRadar/GitHub.swift`.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌘1 / ⌘2 / ⌘3 | Inbox / Pull Requests / Actions |
| ⌘R | Refresh |
| ⌘F / ⇧⌘F | Search / filter the sidebar |
| ⌘O / ⇧⌘C | Open in browser / copy link |
| ⇧⌘U / ⌃⌘A | Mark as read / mark as done |
| ⇧⌘R / ⌥⌘R | Re-run failed jobs / re-run all jobs |
| ⌘. | Cancel run |

## Project layout

```
Sources/RepoRadar/
├── RepoRadarApp.swift   # scenes: main window, menu bar extra, settings; notification clicks
├── AppState.swift       # observable state, refresh and polling, actions, alerts
├── GitHub.swift         # Keychain, REST client (actor, ETag cache), OAuth device flow
├── Models.swift         # workflow runs, jobs, pull requests, issues, notifications
├── WorkflowGraph.swift  # workflow YAML `needs:` reader and graph layout model
├── Markdown.swift       # block-level GitHub-flavored markdown renderer
├── MainView.swift       # window frame, toolbar status pill, sidebar
├── Chrome.swift         # shared workspace chrome: tabs, search, split panes, status bar
├── InboxView.swift, PullsView.swift, ActionsView.swift
├── Detail.swift         # run, pull request and issue details
├── JobGraphView.swift   # workflow graph with pan, zoom and fit
├── Commands.swift       # menu commands and focused values
├── MenuBarContent.swift, SettingsView.swift, FontTheme.swift
Tests/RepoRadarTests/    # model, graph, markdown and layout tests
```

## Troubleshooting

`clt-env.sh` works around a known broken Command Line Tools install: stale 2024 `PackageDescription` interfaces, and a macOS 27 SDK whose SwiftUI macro plugin only ships with Xcode. It only applies when the package manifest fails to load, so it's a no-op on a healthy toolchain. For the same reason the code avoids the `@Entry` and `#Preview` macros.

## Acknowledgements

The workbench layout (filter tabs, search row, table/detail split, status bar) was inspired by [Rockxy](https://github.com/RockxyApp/Rockxy). Only the design was used as a reference, not its code.
