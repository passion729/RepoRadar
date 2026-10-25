# RepoRadar

A native macOS app that answers one question across every repository you work on: **what needs you right now?** Review requests, failing workflows, deployments waiting for approval and mentions land in one ranked queue. The GitHub notifications inbox, pull requests and Actions runs each have their own page.

Built with SwiftUI and Liquid Glass for macOS 26, packaged with Swift Package Manager. No Xcode project needed.

## Features

**Now** (⌘1)
- Four numbers up top: reviews waiting, failing workflows, running now, unread
- **Needs you**: one queue ranked by urgency, then age. Duplicates are merged, so a PR that asks for your review and also has a notification shows once
- Act on the selected item in place: approve, request changes, comment, merge, re-run failed jobs, approve a deployment, reply to a mention
- Every action is optimistic and can be undone for 4 seconds (⌘Z or the toast). Done (E) and Snooze (S) hide an item until something new happens on it
- An inspector (⌥⌘I) with running workflows, their expected time left, and each repository's default-branch health

**Inbox** (⌘2)
- GitHub notifications filtered by Unread, Participating, Mentions, CI, or All, grouped by time or repository; bot notifications are bundled
- A thread view with the full conversation, linked pull request, and a reply box that keeps your draft
- Mark read (⇧⌘U), done (⌃⌘A), snooze, or mute a thread. Opening a thread marks it read after a short delay

**Pull Requests** (⌘3)
- Lists for Waiting on you, Yours and Mentioned, each with readiness dots (checks, reviews, mergeable)
- A readiness bar that says what blocks the merge, with the merge method, auto-merge and Update branch
- Overview with a checks timeline and reviewers (including teams), Files with a diff and a viewed toggle, Checks, Conversation
- A review bar for comment, approve or request changes (⌘↵ submits)

**Actions** (⌘4)
- Every workflow's latest run with a pass/fail strip of its history, filtered by Failing, Running or Waiting. Disabled workflows are hidden
- A job graph laid out by `needs:`, with large matrices collapsed, failure paths in red, zoom (⌘- / ⌘=) and Fit
- Job logs with sections, ANSI color, the failing lines pulled to the top, a minimap, and a separate log window
- Re-run failed (⇧⌘R), re-run all (⌥⌘R), re-run one job, or cancel (⌘., with confirmation)

**Everywhere**
- Search or jump to anything with ⌘K: `repo:`, `author:`, `reason:` (e.g. `reason:review_requested`), `#123` and free words
- Filter repositories from the toolbar: scope every page to one repository, pin up to 8 to the sidebar, or leave repositories and whole owners out of every list
- Menu bar icon with a colored dot when something needs you, and a panel with the counts, the top of the queue, and running workflows (with "notify me when these finish")
- System alerts only for what matters (a push of yours failed, a review request, a mention, a deployment waiting), with Re-run, Approve and Open buttons. Pause them for an hour from the toolbar bell
- Dock badge with the Needs-you count
- Polls with ETags and honors `X-Poll-Interval` and rate limits; the sidebar shows sync state and API quota
- Controls the token can't use are greyed out and say which scope is missing
- Light and dark appearance, VoiceOver labels and actions, Reduce Motion, custom fonts and text size (Settings → Appearance)

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

Open **Settings (⌘,) → Account** and pick one:

- **Use GitHub CLI account**: shown when `gh` is installed and logged in. RepoRadar asks `gh auth token` for the token each time and stores nothing itself.
- **Sign in with GitHub**: the OAuth device flow. The code is copied for you and github.com opens to approve it. No password or client secret is involved.
- **Paste a personal access token** with the `repo`, `notifications` and `read:org` scopes. `read:org` is read-only and lets pull requests show team reviewers.

Device-flow and pasted tokens are stored in the macOS Keychain. Debug builds also read `REPORADAR_TOKEN` or `~/.reporadar-dev-token`, so rebuilding doesn't trigger Keychain prompts.

To use your own OAuth App, enable **Device Flow** in its settings and replace `DeviceFlow.clientID` in `Sources/RepoRadar/GitHub.swift`.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌘1 – ⌘4 | Now / Inbox / Pull Requests / Actions |
| ⌘K or ⌘F | Search or jump to |
| ⌥⌘I | Show or hide Running and Health |
| ⌘R | Refresh |
| ⌘Z | Undo the last action |
| ⌘0 | Open RepoRadar (also from the menu bar panel) |
| J / K | Next / previous item in a list |
| ↵ | Expand or collapse the item |
| A / R | Approve / re-run failed jobs |
| ⇧⌘M | Squash and merge |
| E / S / M | Done / snooze / mute thread |
| ⇧⌘U / ⌃⌘A | Mark notification read / done |
| ⇧⌘R / ⌥⌘R / ⌘. | Re-run failed / re-run all / cancel run |
| ⌘O / ⇧⌘C | Open in browser / copy link |
| ⌘↵ | Send a reply, comment or review |

Single-letter keys work only while a list has focus, never while typing.

## Project layout

```
Sources/RepoRadar/
├── RepoRadarApp.swift      # scenes, notification categories and clicks
├── Config.swift            # tunable defaults: undo window, refresh cadence, Dock badge, bot logins
├── Theme.swift             # color, type and spacing tokens
├── Components/             # buttons, labels, segmented control, toast, split panes, run cells
├── AppState.swift          # observable state, sync loops, actions, alerts
├── NeedsYou.swift          # the Needs-you engine: ranking, dedupe, done and snooze
├── ActionQueue.swift       # optimistic actions with undo
├── GitHub.swift            # REST and GraphQL client (ETags, rate limits), Keychain, device flow
├── GitHubCLI.swift         # sign-in through the GitHub CLI
├── Models.swift, Insights.swift, InboxModel.swift, Workflows.swift, JobLog.swift, Jump.swift
├── MainView.swift          # window, sidebar, toolbar
├── ToolbarControls.swift   # repository filter, alert settings, account
├── NowView.swift, QueueView.swift
├── InboxView.swift, ThreadView.swift, Detail.swift, AutoRead.swift
├── PullsView.swift, PullDetailView.swift
├── ActionsView.swift, RunDetailView.swift, WorkflowGraph.swift, JobGraphView.swift
├── MenuBarContent.swift, Alerts.swift, Commands.swift
├── SettingsView.swift, FontTheme.swift, Markdown.swift
Tests/RepoRadarTests/       # engine, page models, alerts and accessibility tests
```

## Troubleshooting

`clt-env.sh` works around a known broken Command Line Tools install: stale 2024 `PackageDescription` interfaces, and a macOS 27 SDK whose SwiftUI macro plugin only ships with Xcode. It only applies when the package manifest fails to load, so it's a no-op on a healthy toolchain. For the same reason the code avoids the `@Entry` and `#Preview` macros.

Job logs older than the repository's retention (90 days by default) are gone from GitHub; RepoRadar says so instead of showing them.

## Acknowledgements

[RepoBar](https://github.com/steipete/RepoBar) was a reference for GitHub API usage, and [t3code](https://github.com/pingdotgg/t3code) for signing in through the GitHub CLI. Only the approaches were used, not their code.
