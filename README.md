# neetly

Neetly is a Mac code editor built for **web development** and designed to work with AI agents.

<p align="center">
  <a href="https://github.com/neetozone/neetly/releases/latest/download/neetly-macos.dmg">
    <img src="./docs/assets/macos-badge.png" alt="Download neetly for macOS" width="180" />
  </a>
</p>

## Features

* **Built in Browser** - each tab/session gets its own browser.
* **Worktree enabled** - each tab/session gets its own worktree.
* **detach session** - once the work is done, detach from the session. You can attach to the session at any time later. When you attach to the session, then Claude also resumes from where you left off with full context.
* **See PR status** - you can see the status of the PR in the session panel.
* **Custom layout** -  arrange your pane the way you want. Give 40% to Claude and the rest to the browser.
* **Programmatically open tab** - after starting the server, you want to open the browser at a specific place.
* **small codebase** - Codebase is small enough that you can make changes to meet your needs.
* **One click diff view** - execut Cmd+1 to see the diff. You can use any tool you want to see the diff.

## Installation instructions

1. Download [neetly-macos.dmg](https://github.com/neetozone/neetly/releases/latest/download/neetly-macos.dmg) and open the DMG and drag `neetly.app` to Applications.
2. Set up Claude Code notifications (one-time): Execute the following command to do a one-time setup. It adds hooks to `~/.claude/settings.json` so that neetly
   is notified when Claude is done processing and is waiting. When Claude is done, the session tab turns "green".
    If Claude is waiting for permission, then the session tab turns "red". Clicking a colored session tab also clears the color.

   ```bash
   /Applications/neetly.app/Contents/MacOS/neetly notify_neetly_of_claude_events
   ```

### Build from source

```bash
git clone https://github.com/neetozone/neetly.git
cd neetly
swift build

# Symlink the CLI to your PATH
ln -sf $(pwd)/.build/arm64-apple-macosx/debug/neetly /usr/local/bin/neetly

# Run
swift run neetly-app
```

## Resetting to the default settings

Neetly's default settings — the worktree directory, the diff command, and the
post-create command — are baked into the app. If you installed Neetly earlier,
your `~/.config/neetly/settings.json` still holds whatever values were current
back then, so newer defaults don't apply on their own.

To adopt the current defaults, update to the latest Neetly release, then delete
the settings file and restart the app:

```bash
rm ~/.config/neetly/settings.json
```

This resets only the settings file. `repos.json`, `sessions.json`, and
`activities.json` are left untouched, so your repos, open sessions, and history
are preserved. Existing worktrees also stay where they are — only worktrees
created after the reset use the new worktree directory.

## Tech Stack

<p>
 <a href="https://www.swift.org/"><img src="https://img.shields.io/badge/Swift-F05138?logo=swift&logoColor=white" alt="Swift"></a>
 <a href="https://developer.apple.com/xcode/swiftui/"><img src="https://img.shields.io/badge/SwiftUI-0071E3?logo=swift&logoColor=white" alt="SwiftUI"></a>
 <a href="https://developer.apple.com/documentation/appkit"><img src="https://img.shields.io/badge/AppKit-333333?logo=apple&logoColor=white" alt="AppKit"></a>
 <a href="https://github.com/ghostty-org/ghostty"><img src="https://img.shields.io/badge/libghostty-5B2C87?logo=terminal&logoColor=white" alt="libghostty"></a>
 <a href="https://developer.apple.com/documentation/webkit/wkwebview"><img src="https://img.shields.io/badge/WKWebView-006AFF?logo=safari&logoColor=white" alt="WKWebView"></a>
 <a href="https://developer.apple.com/swift/"><img src="https://img.shields.io/badge/Swift_Package_Manager-F05138?logo=swift&logoColor=white" alt="SPM"></a>
</p>

## Viewinig the diff

* Cmd+1 is configured to show you the diff by executing `git diff`. If you want to use a different tool for the diff
  then you can configure it in **Settings**.
* After viewing the diff you can close the diff by executing Cmd+2.
* Here is what Cmd+1 does: opens a new terminal in the right most pane. Executes the **diff command** specified in the **Settings**. Hits Cmd+Shift+m to maximize the window.
* Here is what Cmd+2 does: Hits Cmd+Shift+m to get out of the full screen mode and then kills that tab.

## Layout Config

Declarative pane layout using `split`, `tabs`, `run`, and `visit`:

```yaml
split: columns
left:
  run: claude --dangerously-skip-permissions
right:
  tabs:
    run: bin/setup;bin/launch --neetly
    visit: http://localhost:3000
```

| Key | Value | Children |
|---|---|---|
| `split` | `columns` | `left:` and `right:` |
| `split` | `rows` | `top:` and `bottom:` |
| `tabs` | — | Multiple `run`/`visit` as tabs in one pane |
| `run` | `<command>` | Terminal tab |
| `visit` | `<url>` | Browser tab |
| `size` | `35%` | Percentage of the parent split taken by this child. Optional; defaults to 50/50. |

### Sizing splits

By default, every split is 50/50. Add a `size` attribute to any child to change that:

```yaml
split: columns
left:
  size: 35%
  run: claude --dangerously-skip-permissions
right:
  run: bin/setup;bin/launch --neetly
```

The left pane takes 35% of the width, the right pane takes the remaining 65%. If you specify sizes on both sides and they don't add up to 100%, the first one wins and the second gets the remainder — no error. `size` can appear in any child of a `split` (left/right/top/bottom) and nests naturally.

## CLI Commands

The `neetly` CLI runs in any terminal spawned by' neetly'. It communicates with the app via a Unix domain socket.

### List tabs

```bash
neetly tabs
```

```
TAB  PANE  TYPE      TITLE
--------------------------------------------------
1    1     terminal  claude *
2    2     terminal  bin/launch *
3    2     browser   localhost *
```

### Open a browser tab

```bash
# In current pane (default)
neetly browser open http://localhost:3000

# In a specific pane
neetly browser open http://localhost:3000 --pane 3

# Without stealing focus
neetly browser open http://localhost:3000 --background

# Short alias
neetly visit http://localhost:3000
```

### Send commands to a terminal tab

```bash
# Send "time" + Enter to tab 1
neetly send 1 "time\n"
```

`\n` is converted to a newline (Enter key). `\t` is converted to a tab.

### Open a new terminal tab

```bash
neetly run "npm test"
```

### Session notifications

Change the session tab color to signal status across sessions. Useful when Claude finishes a task while you're working in another session.

```bash
neetly notify              # green (task done)
neetly notify red          # red (Claude needs permission)
neetly notify clear        # reset to normal
```

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| Cmd+T | New terminal tab in focused pane |
| Cmd+Shift+T | New browser tab in focused pane |
| Cmd+W | Close active tab |
| Cmd+K | Clear terminal |
| Cmd+R | Reload browser |
| Cmd+Shift+] | Next tab |
| Cmd+Shift+[ | Previous tab |
| Cmd+Click | Open a URL displayed in the terminal |

## Taxonomy

```
Session (named after your feature/bug, multiple per window)
  Pane (a rectangular region, split horizontally or vertically)
    Tab (terminal or browser — multiple per pane, one visible at a time)
```

## Terminal Appearance

Customize the terminal font, size, and colors by creating `~/.config/neetly/terminal.json`:

```json
{
  "fontFamily": "JetBrains Mono",
  "fontSize": 17,
  "backgroundColor": "#1e1f2e",
  "foregroundColor": "#cdd8f4",
  "selectionColor": "#635b70",
  "linkColor": "#8bb8fa"
}
```

| Field | Description | Default |
|---|---|---|
| `fontFamily` | Any font installed on your system. Falls back to Symbols Nerd Font Mono, Noto Color Emoji, then system monospace. | `JetBrains Mono` |
| `fontSize` | Point size. | `17` |
| `backgroundColor` | Hex color (`#RRGGBB`). | `#1e1f2e` (Catppuccin base) |
| `foregroundColor` | Hex color (`#RRGGBB`). | `#cdd8f4` (Catppuccin text) |
| `selectionColor` | Background color for selected text. | `#635b70` |
| `linkColor` | Overrides ANSI palette blue (colors 4 and 12), where most terminals render URLs. | `#8bb8fa` |
| `scrollback` | Number of lines retained in the scroll-back buffer. | `10000` |

All fields are optional — omit any to use the default. The config is read when each terminal tab is created, so restart neetly to pick up changes.

## Architecture

- **Terminal**: [libghostty](https://github.com/ghostty-org/ghostty) — the embeddable terminal engine from [Ghostty](https://ghostty.org), with GPU (Metal) rendering and Ghostty's full VT emulation. Integrated via the [libghostty-spm](https://github.com/Lakr233/libghostty-spm) Swift package. neetly 1.x used [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (pure Swift, CPU-rendered), which is still bundled as a fallback — set `NEETLY_TERMINAL=swiftterm` to use it. The [2.0 changelog](#changelog) explains the move.
- **Browser**: [WKWebView](https://developer.apple.com/documentation/webkit/wkwebview) is Apple's native web view — the same WebKit engine that powers Safari. It's built into macOS, so neetly ships with zero browser dependencies and no extra download (unlike Electron or CEF which bundle a full Chromium). Every browser tab in neetly is a `WKWebView` embedded directly in the window.

  **Debugging browser tabs with Safari's Web Inspector**: neetly enables `isInspectable` on all browser tabs, so you can use Safari's full Web Inspector (DOM, console, network, breakpoints) against them. One-time setup: Safari → Settings → Advanced → check "Show features for web developers". Then in Safari → Develop → (your Mac name), you'll see all of neetly's open browser tabs listed. Click one to attach the inspector.
- **IPC**: Unix domain socket at `/tmp/neetly-<pid>.sock`
- **Persistence**:
  - `~/.config/neetly/settings.json` — worktree directory, diff command, and post-create command
  - `~/.config/neetly/repos.json` — list of added repos and their default layouts
  - `~/.config/neetly/sessions.json` — open sessions, restored on relaunch
  - `~/.config/neetly/activities.json` — activity history (PRs opened, etc.)
  - `~/.config/neetly/terminal.json` — terminal font and color overrides
  - `~/code/neetly-worktrees/<repo-name>/<branch-name>` — git worktrees are created here, one per session (the base directory is configurable in **Settings**)
- **File watcher**: WKWebView (WebKit) does not support HMR (Hot Module Replacement) the way Chrome's DevTools protocol does, so neetly polls the repo every 2 seconds for changes to JavaScript/React/CSS files and triggers a browser reload when anything changes.

# FAQ

### What is WKWebView

Please see [this](https://github.com/neetozone/neetly/blob/main/docs/wkwebview.md).

### Why you are not using Google Chrome

Google chrome would be nice but that is a much more heavy lift. I noticed that
WKWebView gets 98% of my work done. For the remaining 2% cases I open Google Chrome
and do the work there.

## Changelog

### 2.0 — libghostty

- **New terminal engine.** neetly's terminal is now powered by
  [libghostty](https://github.com/ghostty-org/ghostty) — the engine behind the
  [Ghostty](https://ghostty.org) terminal — replacing SwiftTerm. It brings GPU
  (Metal) rendering and Ghostty's battle-tested VT emulation, and fixes a class
  of reflow, scrolling, and input bugs. SwiftTerm stays bundled as a fallback
  (`NEETLY_TERMINAL=swiftterm`).
- **New app icon.**

neetly **1.0 through 1.0.37** used [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm),
a pure-Swift, CPU-rendered terminal. **2.0** is the first release on libghostty —
a change big enough to earn the major version bump.

---

### Why we moved to libghostty

The long version, for anyone curious about the engineering behind 2.0.

**What pushed it.** SwiftTerm served neetly well through the 1.x line. But as
more people put it through real work, a class of terminal bugs showed up and
stuck: text not reflowing cleanly when a pane was resized, scrolling glitches,
overlapping glyphs, and — occasionally — a typed character arriving twice (`ls`
coming out as `lss`). People who had carefully tuned terminal setups elsewhere
found those setups didn't behave the same here. In one round of testing,
roughly 25 of 30 people hit a terminal issue. That moved the terminal from
"good enough" to "the thing holding the product back."

**Why not earlier.** libghostty had been evaluated before and set aside — the
integration wasn't trivial and, at the time, the stability concerns were too
vague to justify the cost. What changed was that the concerns stopped being
vague: widespread, reproducible failures in real use.

**What libghostty is.** A terminal is really three parts: a pseudo-terminal
(PTY) running your shell; an *emulator* that turns the shell's byte stream into
a grid of cells — tracking colors, the cursor, scrollback, and line reflow;
and a *renderer* that draws that grid. The emulator is the hardest, most
bug-prone part. libghostty is that machinery, extracted from
[Ghostty](https://ghostty.org) as an embeddable library and proven by
Ghostty's large user base. It comes in two layers: `libghostty-vt`, the
emulator core on its own (you supply the renderer), and a full surface API
that bundles the emulator with Ghostty's GPU renderer and input pipeline,
ready to host in a native view.

**The architecture choice.** neetly's bugs spanned both rendering (reflow,
overlap) and input (doubled keystrokes). Taking only the emulator core would
have meant writing our own renderer and input handling — re-deriving, and
re-owning the bugs of, exactly the layers that were failing. So neetly uses
the full surface API: Ghostty's actual renderer and input pipeline. The
terminal in neetly 2.0 is, under the hood, the same machine as Ghostty.

**The dependency choice.** Upstream libghostty doesn't ship a prebuilt binary
for embedding. The options were to build the framework ourselves — which means
maintaining a Ghostty fork and CI, as other embedders do — or to use
[libghostty-spm](https://github.com/Lakr233/libghostty-spm), a community Swift
package that bundles a prebuilt binary with a Swift wrapper around the AppKit
hosting, input, and IME handling. neetly uses libghostty-spm: that wrapper is
the genuinely hard part, it's MIT-licensed (so the lock-in is soft — worst
case the package can be forked), and building our own pipeline would have been
speculative work against a problem we don't have. The rule throughout: act on
concrete needs, not on a feeling of control.

**How it rolled out.** The migration went in stages. First an isolated,
throwaway target proved libghostty could embed and run a real shell at all.
Then the real integration landed behind a runtime switch — both terminal
backends conform to one `TerminalTab` interface, so the rest of the app never
had to care which engine is active, and the swap happens at a single point.
A private beta build, on its own update channel so it never reached public
users, put libghostty in front of testers. Once it worked for every tester it
was handed to, it became the default for everyone in 2.0 — with SwiftTerm kept
in the build as a fallback for anyone who hits a rough edge.
