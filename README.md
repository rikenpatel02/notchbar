# NotchBar

A macOS menu bar app that shows a "Dynamic Island" for live activities, Claude Code and system stats.

![NotchBar expanded panel with clock, CPU and memory gauges, top apps and Claude Code sessions](docs/images/hero.png)

- **Macs with a notch:** the island wraps around the hardware notch. That area is dead space, so it never covers menu bar icons.
- **Macs without a notch:** it works like Live Activities in macOS Tahoe. The compact view is a menu bar item, and clicking it drops the expanded view down *below* the menu bar. Right-click the item for settings.

## Menu bar item
Always shows, left to right:
- **Claude:** "Working" / "N working", or "Approve" when a permission card is waiting
- **CPU:** share of all cores busy over the last second. Turns orange at 75% and red at 90%
- **MEM:** Activity Monitor's "Memory Used" as a share of RAM. Its color follows macOS **memory pressure**, not the percent (macOS keeps RAM full on purpose), so it only turns orange or red when memory is actually short
- **Network:** download and upload rates across Wi-Fi, Ethernet and cellular

Turn the stats off with **Show Stats in Menu Bar** in the right-click menu. Sampling then stops.

<table>
  <tr>
    <td width="50%"><img src="docs/images/approve.png" alt="Approve or deny a Claude Code tool call from the island"></td>
    <td width="50%"><img src="docs/images/banner.png" alt="Live activity banner when Claude finishes"></td>
  </tr>
  <tr>
    <td align="center"><b>Approve or deny</b> Claude Code tool calls</td>
    <td align="center"><b>Live banners</b> when Claude finishes or needs you</td>
  </tr>
</table>

## Expanded panel
- Shortcuts (Downloads, Screenshot, System Settings), battery, clock
- **Live stats:** CPU and memory gauges, network rates, and swap in use (orange once swap passes a quarter of RAM)
- **Top apps:** the three biggest users by Memory or CPU. Helper processes are folded into their app (all of Chrome's renderers count as Chrome). Hover a row for **Quit**, then click **Quit?** to confirm
- **Claude sessions:** project, last tool, and a timer for how long it has been working. Click a row to bring that session's terminal tab to the front. A shield icon marks sessions running with `--dangerously-skip-permissions`

Hovering expands it and moving away collapses it. Opened with a click, the menu or the CLI, it stays open until you click outside it.

## Build & run
```bash
./build.sh --install    # build, copy to /Applications, launch (registers Launch at Login on first run)
./build.sh --run        # run the local build without installing
```
You need macOS 13 or later and a Swift toolchain (the Xcode Command Line Tools are enough). Turn Launch at Login on or off from the right-click menu.

## Claude Code
Add NotchBar as a command hook in `~/.claude/settings.json` (install the app to `/Applications` first). Merge this into any `hooks` you already have:

```json
{
  "hooks": {
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "/Applications/NotchBar.app/Contents/MacOS/NotchBar hook", "timeout": 5 }] }],
    "PreToolUse":       [{ "hooks": [{ "type": "command", "command": "/Applications/NotchBar.app/Contents/MacOS/NotchBar hook", "timeout": 5 }] }],
    "Notification":     [{ "hooks": [{ "type": "command", "command": "/Applications/NotchBar.app/Contents/MacOS/NotchBar hook", "timeout": 5 }] }],
    "Stop":             [{ "hooks": [{ "type": "command", "command": "/Applications/NotchBar.app/Contents/MacOS/NotchBar hook", "timeout": 5 }] }],
    "SessionEnd":       [{ "hooks": [{ "type": "command", "command": "/Applications/NotchBar.app/Contents/MacOS/NotchBar hook", "timeout": 5 }] }],
    "PermissionRequest":[{ "hooks": [{ "type": "command", "command": "/Applications/NotchBar.app/Contents/MacOS/NotchBar hook", "timeout": 130 }] }]
  }
}
```

The hook reports the session's tty, terminal app (`TERM_PROGRAM`) and permission mode along with each event.

- **Working / Done / Waiting:** live status in the menu bar item, the session list, and banners. Banners are skipped when that session's terminal tab is already the one in front (Terminal and iTerm2).
- **PermissionRequest:** the island opens with an Approve/Deny card and the hook waits for your choice. If you don't answer within 120s (override with `NOTCHBAR_PERMISSION_TIMEOUT`, and keep the hook `timeout` above it), the hook exits without a decision and Claude falls back to its normal terminal prompt. If NotchBar isn't running, the hook exits immediately.
- **Skip-permissions sessions:** sessions started with `--dangerously-skip-permissions` never ask, so no cards appear for them. Start Claude without that flag to approve from the island.
- **Sessions started before NotchBar (optional):** if you already have a hook that writes one JSON file per session to `~/.claude/status/` (fields `session_id`, `project`, `status`, `updated_at`, `tty`, `term`, `message`), NotchBar restores those sessions at launch and every 30s, keeping only terminals that still run `claude`. Without it, sessions appear from their next hook event.

Jumping to a terminal tab and checking which tab is in front use AppleScript, so macOS asks once for permission to control Terminal (System Settings > Privacy & Security > Automation). Because the app is ad-hoc signed, a rebuild may ask again.

## Drive it from scripts
```bash
B=build/NotchBar.app/Contents/MacOS/NotchBar
$B toast "Build passed" "notchbar - 12s" checkmark.circle.fill green
$B open | close | toggle | hide | show
```
Commands are sent to the running app as a distributed notification, so scripts and hooks need no extra permissions.

## Demo mode
`NOTCHBAR_DEMO=1 build/NotchBar.app/Contents/MacOS/NotchBar` shows sample sessions and apps instead of your own, and ignores real Claude Code events. Use it for screenshots; Quit is disabled while it runs.

## Privacy
Everything stays on your Mac. NotchBar makes no network requests and collects nothing; the network meter only reads interface byte counters. Claude Code events travel between the hook and the app as local distributed notifications.

## License
MIT. See [LICENSE](LICENSE).
