# neetly1

A terminal multiplexer with browser panes, built on SwiftTerm and WKWebView.

## Install

```bash
# Build
swift build

# Symlink the CLI to your PATH
ln -sf $(pwd)/.build/arm64-apple-macosx/debug/neetly /usr/local/bin/neetly
```

## Run

```bash
swift run neetly1
```

On first launch, add a repo and configure its default layout. Repos are persisted at `~/.config/neetly1/repos.json`.

## Layout Config

Declarative pane layout using `split`, `run`, and `visit`:

```yaml
split: columns
left:
  run: claude
right:
  split: rows
  top:
    run: bin/launch
  bottom:
    visit: https://neeto.com
```

| Key | Value | Children |
|---|---|---|
| `split` | `columns` | `left:` and `right:` |
| `split` | `rows` | `top:` and `bottom:` |
| `run` | `<command>` | Terminal tab |
| `visit` | `<url>` | Browser tab |

## CLI Commands

The `neetly` CLI runs from inside any terminal spawned by neetly1. It communicates with the app via a Unix domain socket.

### List tabs

```bash
neetly tabs
```

```
TAB  PANE  TYPE      TITLE
--------------------------------------------------
1    1     terminal  claude *
2    2     terminal  bin/launch *
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

### Send text to a terminal tab

```bash
# Send "time" + Enter to tab 1
neetly send 1 "time\n"
```

`\n` is converted to a newline (Enter key). `\t` is converted to a tab.

### Open a new terminal tab

```bash
neetly run "npm test"
```

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| Cmd+T | New terminal tab in focused pane |
| Cmd+Shift+T | New browser tab in focused pane |
| Cmd+Shift+] | Next tab |
| Cmd+Shift+[ | Previous tab |

## Taxonomy

```
Workspace (one per session, named after your feature/bug)
  Window (the macOS window)
    Pane (a rectangular region, split horizontally or vertically)
      Tab (terminal or browser — multiple per pane, one visible at a time)
```

## Architecture

- **Terminal**: [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (upgrade path to libghostty for GPU rendering)
- **Browser**: WKWebView (native macOS WebKit, zero dependencies)
- **IPC**: Unix domain socket at `/tmp/neetly1-<pid>.sock`
- **Persistence**: `~/.config/neetly1/repos.json`
