# PoohBooLock 🐾

[![Latest release](https://img.shields.io/github/v/release/minimapletinytools/kitten-key-lock)](https://github.com/minimapletinytools/kitten-key-lock/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

<img src="docs/icon.png" width="112" align="right" alt="PoohBooLock icon">

A tiny macOS menu-bar utility that locks the keyboard so your cats can't type on it.

The app is **PoohBooLock** (named after the cat); the repo is [`kitten-key-lock`](https://github.com/minimapletinytools/kitten-key-lock).

Two lock modes are available from the menu bar:

| Mode | What is blocked | Menu bar when locked |
| --- | --- | --- |
| **Built-in Keyboard Only** | The MacBook's built-in keyboard. External keyboards and the trackpad keep working. | 🐱 cat |
| **All Keyboards** | Every keyboard, including USB and Bluetooth. The trackpad and mouse keep working. | 😺 cat in a circle |

Both modes are unlocked with **C**, **A** and **T**, or by choosing **Unlock Keyboard** from the menu:

- **All Keyboards** mode: the sequence works from **either** keyboard, together or in quick succession.
- **Built-in Keyboard Only** mode: use the built-in keyboard, or press the three keys **together** on an external keyboard. Normal typing on the external keyboard is left untouched.

## Download and install (easiest)

No build tools needed:

1. Open the [latest release](https://github.com/minimapletinytools/kitten-key-lock/releases/latest).
2. Download `PoohBooLock.zip` and unzip it.
3. Right-click **install.command** → **Open**. It installs the app to `/Applications` (or `~/Applications`), clears the macOS quarantine flag, and launches it.
   - Manual alternative: drag `PoohBooLock.app` to `/Applications` and right-click → **Open**.
4. Install and run [Karabiner-Elements](https://karabiner-elements.pqrs.org). PoohBooLock adds one small rule to the active Karabiner profile and needs Karabiner running.

The release is a **universal** build (Apple Silicon + Intel), built by GitHub Actions from this source. It is **ad-hoc signed and not notarized** — there is no paid Apple Developer ID involved — so macOS Gatekeeper warns on the first launch. `install.command` (or right-click → Open) handles that. This is the same situation as building it yourself.

## Requirements

- macOS 13 or later (tested on macOS 26.5).
- [Karabiner-Elements](https://karabiner-elements.pqrs.org) installed **and running**. Tested with Karabiner-Elements 16.0.0.
- **No Accessibility or Input Monitoring permission is needed.**

## Install from source

```bash
git clone https://github.com/minimapletinytools/kitten-key-lock.git
cd kitten-key-lock
./install.sh
```

`install.sh` builds the app, installs it to `/Applications/PoohBooLock.app` (or `~/Applications` if `/Applications` isn't writable), and launches it. The app is ad-hoc signed because it is built locally; no Apple Developer account is needed.

## Use

Click the pawprint and choose one of:

- **Lock Built-in Keyboard Only** — the laptop keyboard goes dead. An external keyboard and the trackpad keep working.
- **Lock All Keyboards** — every keyboard goes dead, including USB and Bluetooth ones. The trackpad and mouse keep working.

While locked, the menu shows which mode is active:

- **Built-in Keyboard Locked** → **Also Lock External Keyboards** switches to all-keyboards mode without unlocking.
- **All Keyboards Locked** → **Only Lock Built-in Keyboard** re-enables external keyboards while keeping the laptop keyboard locked.

Unlock in either mode by pressing **C**, **A** and **T**, or by choosing **Unlock Keyboard**.

- In **all-keyboards mode** the sequence works from either keyboard, sequential or together.
- In **built-in-only mode** the built-in keyboard's sequence works sequentially or together. On an external keyboard, press **C + A + T together** to unlock; a normal sequence (or normal typing) is passed through untouched, so the external keyboard stays a normal keyboard. C/A/T on the external may be briefly delayed while the lock is active.
- When the sequence is used as the unlock gesture, the keys are swallowed, so it never types "cat" into the current app.
- Pressing any other key clears a partial sequence.
- When the sequence completes, a "Keyboard Unlocked" HUD appears and the icon turns back into the pawprint.

The menu also has:

- **Launch at Login** — installs a small user LaunchAgent (`~/Library/LaunchAgents/com.giraffe.pooboolock.login.plist`).
- **Karabiner Integration**
  - **Reinstall Rule in Current Profile** — useful after switching Karabiner profiles.
  - **Remove PoohBooLock Rule…** — removes the rule from every Karabiner profile.
  - **Reveal Backup Folder** / **Reveal Log**.
- **About PoohBooLock**.
- **Quit and Unlock** — quitting always tries to unlock first.

### Emergency unlock

The easiest rescue is the app's own CLI, which clears both lock variables and updates the icon of a running app:

```bash
"/Applications/PoohBooLock.app/Contents/MacOS/PoohBooLock" --unlock
```

If the app itself is gone, unlock Karabiner directly:

```bash
"/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli" \
  --set-variables '{"pooboolock_locked":0,"pooboolock_all":0}'
```

You can also click the menu icon → **Unlock Keyboard**, relaunch PoohBooLock (launching it always resets to unlocked), or reboot. **The lock never survives a reboot.**

In all-keyboards mode, C/A/T on either keyboard is the escape hatch; if both keyboards are unavailable, use the menu bar with the trackpad/mouse, or reboot.

## How it works

PoohBooLock writes one complex-modification rule named
`PoohBooLock: block the built-in keyboard while locked`
into the **currently selected profile** of `~/.config/karabiner/karabiner.json`.

It uses two Karabiner variables:

- `pooboolock_locked` — `1` while any lock is active.
- `pooboolock_all` — `1` only in all-keyboards mode.

The rule then has:

- **Built-in mode rules** conditioned on `pooboolock_locked = 1` plus
  ```json
  {"type": "device_if", "identifiers": [{"is_built_in_keyboard": true}]}
  ```
  These swallow every `key_code` and `consumer_key_code` from the laptop keyboard.
- **All-keyboards rules** conditioned on `pooboolock_locked = 1` and `pooboolock_all = 1`, with **no** `device_if`. These swallow the same events from every device.
- **C/A/T unlock rules**. On the built-in keyboard the sequence is active in both modes. In all-keyboards mode an external sequence is captured too (that keyboard is blocked anyway). In built-in-only mode an external keyboard only reacts to a deliberate simultaneous C+A+T chord; normal external typing is passed through.
- C, A and T each set a flag and are swallowed; pressing the third one clears `pooboolock_locked` and `pooboolock_all`, clears the flags, and emits a hidden **Control+F20** key.
- The menu-bar app listens for that hidden **Control+F20** marker with a Carbon hot key. That is how the icon, HUD and menu stay in sync without Accessibility permissions. F20 is not a physical MacBook key, and the marker is the only thing that hot key is used for.
- Any other built-in key clears a partial C/A/T sequence.
- Lock/unlock/mode changes use `karabiner_cli --set-variables`, which talks straight to Karabiner's device grabber.

If Karabiner is quit/restarted, the active Karabiner profile changes, or the rule disappears, the app detects it within a few seconds and releases the lock in the UI.

### Why Karabiner?

A plain `CGEventTap` sees **all** keyboards as one stream and cannot reliably tell the built-in keyboard from an external one. Karabiner-Elements already grabs the built-in keyboard at the HID level and exposes a per-device `device_if` condition, which is exactly what is needed for the built-in-only mode. PoohBooLock is a friendly menu-bar front end for those rules.

### Your Karabiner configuration

- A timestamped backup is written to
  `~/Library/Application Support/PoohBooLock/backups/karabiner-*.json`
  before every change to the Karabiner configuration (the last 30 are kept).
- The config **before PoohBooLock was ever used** is preserved as
  `ORIGINAL-karabiner-before-pooboolock.json`
  in that same backup folder.
- The app uses `JSONSerialization`, so the file's whitespace/key order is rewritten when a rule is added. The JSON content and rule order are preserved.
- Karabiner 16.0.0 on this Mac has a pre-existing internal IPC issue that makes Karabiner's own `shell_command` actions fail with "invalid shared secret". PoohBooLock deliberately does **not** use `shell_command` (or any other IPC-dependent Karabiner action), so this doesn't affect the lock or the icon sync.

## Limitations

- **Karabiner-Elements must be installed and running.** If it isn't, the Lock actions show an alert and do nothing.
- **The Touch ID / power button is not a normal keyboard key.** Pressing it can still sleep the Mac.
- **Media keys are blocked** while locked, which is intentional.
- If you **switch Karabiner profiles** while locked, the lock is released (the app notices). Lock again afterward; the rule is installed into the new active profile.
- If the app has quit or crashed, the Karabiner rule still enforces the lock; use the C/A/T sequence, the CLI reset above, or a reboot.
- The C/A/T sequence is intentionally simple. A cat that presses C, A and T with no other keys in between could unlock it; the menu bar remains the reliable path, and you can re-lock immediately.
- In built-in-only mode, an external keyboard only unlocks with a **simultaneous** C+A+T chord; typing "cat" normally is not intercepted.
- **All-keyboards mode** also blocks the external keyboard, so the menu bar (mouse) and the C/A/T sequence on either keyboard are the ways out. Don't enable it if you have no way to click the menu bar and no access to a keyboard.

## Files

| Path | Purpose |
| --- | --- |
| `/Applications/PoohBooLock.app` | The app |
| `~/Library/Application Support/PoohBooLock/pooboolock.log` | App log |
| `~/Library/Application Support/PoohBooLock/backups/` | Karabiner config backups |
| `~/Library/Application Support/PoohBooLock/state` | Lock-state marker (`unlocked`, `locked-builtin`, `locked-all`) |
| `~/Library/LaunchAgents/com.giraffe.pooboolock.login.plist` | Only when Launch at Login is on |
| `~/.config/karabiner/karabiner.json` | Karabiner config (contains the PoohBooLock rule) |

## Project layout

- `Sources/AppDelegate.swift` — menu bar, lock modes, state machine, watchdog, HUD
- `Sources/LockMode.swift` — the two modes and their icons/text
- `Sources/KarabinerConfig.swift` — Karabiner CLI, config editing, the rule
- `Sources/GlobalHotKey.swift` — the permission-free Control+F20 marker listener
- `Sources/HUD.swift` — the little lock/unlock overlay
- `Sources/LoginItem.swift` — the Launch at Login LaunchAgent
- `Sources/Utilities.swift` — process helpers, logging, alerts
- `Sources/main.swift` — entry point + a small debug CLI
- `Tools/make-icon.swift` — generates the pawprint app icon
- `packaging/install.command` — the double-click installer shipped in releases
- `.github/workflows/release.yml` — CI that builds and publishes releases

## Build from source

```bash
./build.sh              # builds dist/PoohBooLock.app for this Mac
UNIVERSAL=1 ./build.sh  # builds a universal arm64 + x86_64 app
./install.sh            # builds, installs, launches
```

The build generates `AppIcon.icns` if it is missing and ad-hoc signs the bundle. No Xcode project is required; it uses the macOS SDK's `swiftc`, `iconutil` and `codesign`.

## Releasing (GitHub Actions)

The workflow [`.github/workflows/release.yml`](.github/workflows/release.yml) runs on every push to `main` (builds a test artifact) and on any `v*` tag. On a tag it builds a universal app, packages `PoohBooLock.zip` (app + `install.command` + SHA-256), and publishes a GitHub release:

```bash
git tag v1.0.1
git push origin v1.0.1
```

If the release step ever gets a permissions error, enable **Settings → Actions → General → Workflow permissions → Read and write permissions** in the repo.

## Debug CLI

The app binary also has a few non-GUI commands:

```bash
/Applications/PoohBooLock.app/Contents/MacOS/PoohBooLock --status
/Applications/PoohBooLock.app/Contents/MacOS/PoohBooLock --self-test
/Applications/PoohBooLock.app/Contents/MacOS/PoohBooLock --lock
/Applications/PoohBooLock.app/Contents/MacOS/PoohBooLock --lock-all
/Applications/PoohBooLock.app/Contents/MacOS/PoohBooLock --unlock
/Applications/PoohBooLock.app/Contents/MacOS/PoohBooLock --install-rule
/Applications/PoohBooLock.app/Contents/MacOS/PoohBooLock --remove-rule
```

`--lock` locks only the built-in keyboard; `--lock-all` locks every keyboard. Both write the state file, so a running app follows along.

## Uninstall

```bash
./uninstall.sh
```

This unlocks, removes the PoohBooLock rule from every Karabiner profile, boots out the login item, removes the app, and leaves the backups/logs in `~/Library/Application Support/PoohBooLock/` (delete that folder for a completely clean removal).

## Troubleshooting

- **The icon doesn't match the mode** — click the menu; the header shows which lock is active. Use **Unlock Keyboard** and re-lock in the desired mode, or use **Reinstall Rule in Current Profile**.
- **Lock says Karabiner isn't running** — start Karabiner-Elements and try again.
- **Keys still type while locked** — open **Karabiner Integration → Reinstall Rule in Current Profile**, then lock again. Make sure the active Karabiner profile is the one the app installed into.
- **All-keyboards mode feels stuck** — use the menu bar (mouse) → **Unlock Keyboard**, or press C/A/T on either keyboard, or run the `--unlock` command above.
- **Log** — `~/Library/Application Support/PoohBooLock/pooboolock.log`, or **Karabiner Integration → Reveal Log**.
- **Karabiner config restore** — the untouched original is in the backups folder as `ORIGINAL-karabiner-before-pooboolock.json`. Restore it with Karabiner quit if you ever want to remove all traces manually.

## License

MIT — see [LICENSE](LICENSE).

---

Made for PoohBoo and friends. 🐾
