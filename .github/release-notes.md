PoohBooLock is a tiny menu-bar cat lock for the MacBook keyboard.

## Two lock modes

- **Lock Built-in Keyboard Only** — the laptop keyboard is blocked; external keyboards and the trackpad keep working.
- **Lock All Keyboards** — every keyboard is blocked, including USB and Bluetooth.

While locked, the pawprint menu also switches between the two modes. Unlock with **C**, **A** and **T** (or the menu's **Unlock Keyboard**).

## Install

1. Download **PoohBooLock.zip** and unzip it.
2. Right-click **install.command** → **Open**. It installs the app to `/Applications`, clears the macOS quarantine flag, and launches it.
   (Manual alternative: drag `PoohBooLock.app` to `/Applications` and right-click → **Open**.)
3. Install and run [Karabiner-Elements](https://karabiner-elements.pqrs.org). PoohBooLock adds one small rule to the active Karabiner profile and needs Karabiner running.

## Notes

- Requires macOS 13 or later.
- The app is built from source by GitHub Actions, ad-hoc signed, and **not notarized**. macOS Gatekeeper will warn on the first launch; `install.command` / right-click → Open is the workaround. There is no Apple Developer ID involved.
- This release is a universal binary (Apple Silicon + Intel).
- The SHA-256 of the zip is in `PoohBooLock.zip.sha256`.
- No Accessibility or Input Monitoring permission is needed.

If the menu icon feels out of sync, click it and use **Unlock Keyboard**; or run:

```bash
"/Applications/PoohBooLock.app/Contents/MacOS/PoohBooLock" --unlock
```
