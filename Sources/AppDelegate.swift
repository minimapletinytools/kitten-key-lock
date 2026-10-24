import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let karabiner = KarabinerController.shared
    private let hud = HUDController()
    private let unlockMarkerHotKey = GlobalHotKey()

    private var statusItem: NSStatusItem!
    private var locked = false
    private var lockedMode: LockMode = .builtInOnly
    private var lockInProgress = false
    private var startupResetInProgress = false
    private var lockedProfileName: String?
    private var coreSignatureAtLock: String?

    private var watchdogTimer: Timer?
    private var watchdogBusy = false

    private var stateWatcher: DispatchSourceFileSystemObject?
    private var stateFileDescriptor: Int32 = -1

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        ensureSupportDirectory()
        NSApp.setActivationPolicy(.accessory)

        pblLog("launching \(AppInfo.name) \(AppInfo.version); karabinerInstalled=\(karabiner.isInstalled)")

        setupStatusItem()
        updateStatusItem()

        _ = unlockMarkerHotKey.register(keyCode: UnlockMarker.keyCode,
                                        modifiers: UnlockMarker.modifiers) { [weak self] in
            self?.handleUnlockMarker()
        }

        writeStateFile("unlocked")
        startStateWatcher()
        startStartupReset()

        showReadyHUDIfNeeded()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
            pblLog("status item: visible=\(self.statusItem.isVisible) "
                   + "button=\(self.statusItem.button != nil) "
                   + "image=\(self.statusItem.button?.image != nil)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        unlockMarkerHotKey.unregister()
        stopStateWatcher()
        stopWatchdog()
        pblLog("terminated")
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if locked {
            pblLog("quit requested while locked; trying to unlock first")
            do {
                try karabiner.setLockMode(nil, timeout: 2)
                writeStateFile("unlocked")
                locked = false
            } catch {
                pblLog("unlock on quit failed: \(error.localizedDescription)")
                writeStateFile("unlocked")
                locked = false
            }
        }
        return .terminateNow
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: - Startup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.appearsDisabled = false
        }
    }

    /// Every launch starts unlocked. This makes crashes (or a stale CLI lock)
    /// harmless: opening the app always restores the keyboard.
    private func startStartupReset() {
        guard karabiner.isInstalled else {
            pblLog("Karabiner is not installed; nothing to reset")
            return
        }
        guard !startupResetInProgress else { return }
        startupResetInProgress = true
        pblLog("startup reset: ensuring the Karabiner lock variables are cleared")

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            do {
                try self.karabiner.setLockMode(nil, timeout: 3)
                pblLog("startup reset: lock variables cleared")
            } catch {
                pblLog("startup reset failed: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                self.startupResetInProgress = false
            }
        }
    }

    private func showReadyHUDIfNeeded() {
        let key = "didShowReadyHUD"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            self?.hud.show(title: "PoohBooLock is ready",
                           subtitle: "Click the pawprint in the menu bar to lock the built-in keyboard",
                           symbol: "pawprint.fill",
                           duration: 4.0)
        }
    }

    // MARK: - Status item and menu

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }

        let symbol = locked ? lockedMode.statusSymbol : "pawprint"
        let fallback = locked ? "lock.fill" : "keyboard"
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)

        let description: String
        if !locked {
            description = "PoohBooLock, keyboards unlocked"
        } else if lockedMode == .allKeyboards {
            description = "PoohBooLock, all keyboards locked"
        } else {
            description = "PoohBooLock, built-in keyboard locked"
        }

        // cat.fill / cat.circle.fill arrived in a later SF Symbols release;
        // keep a usable icon if the app is ever run on an older macOS.
        let image = (NSImage(systemSymbolName: symbol,
                             accessibilityDescription: description)?
            .withSymbolConfiguration(configuration))
            ?? (NSImage(systemSymbolName: fallback,
                        accessibilityDescription: description)?
                .withSymbolConfiguration(configuration))
        image?.isTemplate = true
        button.image = image

        switch (locked, lockedMode) {
        case (false, _):
            button.toolTip = "PoohBooLock — click to lock the keyboard"
        case (true, .builtInOnly):
            button.toolTip = "PoohBooLock — built-in keyboard locked "
                + "(press \(AppInfo.unlockCombo) to unlock)"
        case (true, .allKeyboards):
            button.toolTip = "PoohBooLock — all keyboards locked "
                + "(press \(AppInfo.unlockCombo) to unlock)"
        }
        button.setAccessibilityLabel(button.toolTip ?? AppInfo.name)
        statusItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if !karabiner.isInstalled {
            addDisabledItem(to: menu, title: "Karabiner-Elements not found")
            menu.addItem(.separator())
        }

        if locked {
            addDisabledItem(to: menu, title: lockedMode.lockedTitle)

            let unlock = NSMenuItem(title: "Unlock Keyboard",
                                    action: #selector(unlockAction),
                                    keyEquivalent: "")
            unlock.target = self
            unlock.image = symbolImage("lock.open")
            menu.addItem(unlock)

            switch lockedMode {
            case .builtInOnly:
                let all = NSMenuItem(title: "Also Lock External Keyboards",
                                     action: #selector(lockAllKeyboardsAction),
                                     keyEquivalent: "")
                all.target = self
                all.image = symbolImage(LockMode.allKeyboards.menuSymbol)
                menu.addItem(all)
            case .allKeyboards:
                let builtIn = NSMenuItem(title: "Only Lock Built-in Keyboard",
                                         action: #selector(lockBuiltInOnlyAction),
                                         keyEquivalent: "")
                builtIn.target = self
                builtIn.image = symbolImage(LockMode.builtInOnly.menuSymbol)
                menu.addItem(builtIn)
            }

            addDisabledItem(to: menu, title: "Press \(AppInfo.unlockCombo) to unlock")
        } else {
            let builtIn = NSMenuItem(title: "Lock Built-in Keyboard Only",
                                     action: #selector(lockBuiltInOnlyAction),
                                     keyEquivalent: "")
            builtIn.target = self
            builtIn.image = symbolImage(LockMode.builtInOnly.menuSymbol)
            menu.addItem(builtIn)

            let all = NSMenuItem(title: "Lock All Keyboards",
                                 action: #selector(lockAllKeyboardsAction),
                                 keyEquivalent: "")
            all.target = self
            all.image = symbolImage(LockMode.allKeyboards.menuSymbol)
            menu.addItem(all)

            addDisabledItem(to: menu, title: "Unlock: press \(AppInfo.unlockCombo)")
        }

        menu.addItem(.separator())

        let about = NSMenuItem(title: "About PoohBooLock",
                               action: #selector(aboutAction),
                               keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let login = NSMenuItem(title: "Launch at Login",
                               action: #selector(toggleLoginItemAction),
                               keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabledForCurrentApp ? .on : .off
        menu.addItem(login)

        let integration = NSMenuItem(title: "Karabiner Integration",
                                     action: nil,
                                     keyEquivalent: "")
        integration.submenu = makeIntegrationMenu()
        integration.isEnabled = true
        menu.addItem(integration)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: locked ? "Quit and Unlock" : "Quit PoohBooLock",
                              action: #selector(quitAction),
                              keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    private func makeIntegrationMenu() -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        let reinstall = NSMenuItem(title: "Reinstall Rule in Current Profile",
                                   action: #selector(reinstallRuleAction),
                                   keyEquivalent: "")
        reinstall.target = self
        reinstall.isEnabled = karabiner.isInstalled
        submenu.addItem(reinstall)

        let remove = NSMenuItem(title: "Remove PoohBooLock Rule…",
                                action: #selector(removeRuleAction),
                                keyEquivalent: "")
        remove.target = self
        remove.isEnabled = karabiner.isInstalled
        submenu.addItem(remove)

        submenu.addItem(.separator())

        let backups = NSMenuItem(title: "Reveal Backup Folder",
                                 action: #selector(revealBackupsAction),
                                 keyEquivalent: "")
        backups.target = self
        submenu.addItem(backups)

        let log = NSMenuItem(title: "Reveal Log",
                             action: #selector(revealLogAction),
                             keyEquivalent: "")
        log.target = self
        submenu.addItem(log)

        return submenu
    }

    private func addDisabledItem(to menu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    // MARK: - Actions

    @objc private func lockBuiltInOnlyAction() {
        if locked {
            switchLockMode(to: .builtInOnly)
        } else {
            beginLock(mode: .builtInOnly)
        }
    }

    @objc private func lockAllKeyboardsAction() {
        if locked {
            switchLockMode(to: .allKeyboards)
        } else {
            beginLock(mode: .allKeyboards)
        }
    }

    private func beginLock(mode: LockMode) {
        guard !locked, !lockInProgress else { return }

        if startupResetInProgress {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.beginLock(mode: mode)
            }
            return
        }

        guard karabiner.isInstalled else {
            showMissingKarabinerAlert()
            return
        }
        guard let profile = karabiner.runningProfileName() else {
            showKarabinerNotRunningAlert()
            return
        }

        lockInProgress = true
        do {
            let inserted = try KarabinerConfig.ensureRule(profileName: profile)
            if inserted {
                pblLog("installed PoohBooLock rule into profile “\(profile)”; waiting for Karabiner to reload")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    self?.finishLocking(profileName: profile, mode: mode)
                }
            } else {
                finishLocking(profileName: profile, mode: mode)
            }
        } catch {
            lockInProgress = false
            showErrorAlert(title: "Couldn't lock the keyboard",
                           message: error.localizedDescription)
        }
    }

    private func finishLocking(profileName: String, mode: LockMode) {
        guard !locked else {
            lockInProgress = false
            return
        }
        do {
            try karabiner.setLockMode(mode)
        } catch {
            lockInProgress = false
            showErrorAlert(title: "Couldn't lock the keyboard",
                           message: "\(error.localizedDescription)\n\n"
                           + "Karabiner-Elements must be running. You can always unlock "
                           + "by pressing C, A, and T on the built-in keyboard.")
            return
        }

        locked = true
        lockedMode = mode
        lockInProgress = false
        lockedProfileName = profileName
        coreSignatureAtLock = karabiner.coreServiceSignature()
        writeStateFile(mode.stateValue)
        startWatchdog()
        updateStatusItem()

        hud.show(title: mode.lockedTitle,
                 subtitle: mode.lockHUDSubtitle,
                 symbol: mode.statusSymbol)
        pblLog("locked (\(mode.rawValue)) using profile “\(profileName)”; "
               + "core signature=\(coreSignatureAtLock ?? "unknown")")
    }

    /// Switching modes while locked: the built-in keyboard stays locked, and
    /// only the external-keyboard part of the rule is turned on or off.
    private func switchLockMode(to mode: LockMode) {
        guard locked, lockedMode != mode, !lockInProgress else { return }
        do {
            try karabiner.setLockMode(mode)
        } catch {
            showErrorAlert(title: "Couldn't change the lock mode",
                           message: error.localizedDescription)
            return
        }

        lockedMode = mode
        writeStateFile(mode.stateValue)
        updateStatusItem()

        let subtitle = mode == .allKeyboards
            ? "External keyboards are locked too · C + A + T to unlock"
            : "External keyboards are usable again · C + A + T to unlock"
        hud.show(title: mode.lockedTitle,
                 subtitle: subtitle,
                 symbol: mode.statusSymbol)
        pblLog("switched lock mode to \(mode.rawValue)")
    }

    /// The Karabiner unlock rule emits Control+F20 after clearing the
    /// variable. The rule itself already unlocked the built-in keyboard; this
    /// just brings the menu bar UI back in sync.
    private func handleUnlockMarker() {
        pblLog("unlock marker received (locked=\(locked))")
        guard locked else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                try self.karabiner.setLockMode(nil, timeout: 2)
            } catch {
                // The Karabiner rule itself already cleared the variable. Do
                // not leave the icon stale just because the extra check failed.
                pblLog("unlock marker: clearing variable failed: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                guard self.locked else { return }
                self.completeUnlock(showHUD: true)
            }
        }
    }

    @objc private func unlockAction() {
        guard locked else { return }
        do {
            try karabiner.setLockMode(nil)
        } catch {
            if karabiner.runningProfileName(timeout: 1.5) == nil {
                pblLog("unlock command failed but Karabiner is not running; releasing UI")
                releaseLock(reason: "Karabiner-Elements is not running")
            } else {
                showErrorAlert(title: "Couldn't unlock the keyboard",
                               message: "\(error.localizedDescription)\n\n"
                               + "Try pressing C, A, and T on the built-in keyboard, "
                               + "or restart Karabiner-Elements.")
            }
            return
        }
        completeUnlock(showHUD: true)
    }

    private func completeUnlock(showHUD: Bool) {
        guard locked else { return }

        locked = false
        lockInProgress = false
        lockedProfileName = nil
        coreSignatureAtLock = nil
        stopWatchdog()
        writeStateFile("unlocked")
        updateStatusItem()

        if showHUD {
            hud.show(title: "Keyboard Unlocked",
                     subtitle: "Cats may type again",
                     symbol: "pawprint.fill")
        }
        pblLog("unlocked")
    }

    private func releaseLock(reason: String) {
        guard locked else { return }
        pblLog("releasing lock: \(reason)")
        completeUnlock(showHUD: false)
        hud.show(title: "Keyboard Unlocked",
                 subtitle: reason,
                 symbol: "exclamationmark.triangle.fill")
    }

    @objc private func aboutAction() {
        let message = """
        A menu-bar cat lock for the MacBook keyboard.

        TWO LOCK MODES
        • Built-in Keyboard Only — blocks the laptop keyboard. External keyboards and the trackpad keep working.
        • All Keyboards — blocks every keyboard, including USB and Bluetooth. You can still unlock with the built-in keyboard or this menu.

        HOW IT WORKS
        PoohBooLock adds a small complex-modification rule to your active Karabiner-Elements profile. Karabiner-Elements must stay running while a keyboard is locked.

        UNLOCK
        Click “Unlock Keyboard” in this menu, or press C, A and T:
        • In all-keyboards mode, on either keyboard — together or in quick succession.
        • In built-in-only mode, on the built-in keyboard — or press all three together on an external keyboard. Normal typing on the external keyboard is left untouched.
        Pressing another key clears a partial sequence.

        YOUR KARABINER CONFIG
        The Karabiner configuration is backed up before every change:
        \(AppInfo.backupsDirectory.path)

        LIMITATIONS
        • The Touch ID / power button is not a normal keyboard key, so pressing it can still sleep the Mac.
        • Media keys are blocked as well.
        • If Karabiner-Elements quits or restarts, the lock is released.

        No Accessibility or Input Monitoring permission is required.
        """
        _ = showAlert(title: "PoohBooLock \(AppInfo.version)",
                      message: message,
                      style: .informational,
                      buttons: ["OK"])
    }

    @objc private func reinstallRuleAction() {
        guard karabiner.isInstalled else {
            showMissingKarabinerAlert()
            return
        }
        guard let profile = karabiner.runningProfileName() else {
            showKarabinerNotRunningAlert()
            return
        }

        do {
            let inserted = try KarabinerConfig.ensureRule(profileName: profile)
            if locked {
                try? karabiner.setLockMode(lockedMode)
            }
            hud.show(title: inserted ? "Karabiner Rule Installed" : "Rule Already Installed",
                     subtitle: "Profile: \(profile)",
                     symbol: "checkmark.circle.fill")
        } catch {
            showErrorAlert(title: "Couldn't update the Karabiner rule",
                           message: error.localizedDescription)
        }
    }

    @objc private func removeRuleAction() {
        guard karabiner.isInstalled else {
            showMissingKarabinerAlert()
            return
        }

        let choice = showAlert(
            title: "Remove PoohBooLock from Karabiner?",
            message: "This deletes the PoohBooLock rule from every Karabiner profile. "
            + "The keyboard(s) will work normally, and the Lock menu items won't block anything until the rule is installed again.\n\n"
            + "The rule is reinstalled automatically the next time you click Lock. "
            + "A backup of karabiner.json is saved first.",
            style: .warning,
            buttons: ["Remove Rule", "Cancel"])
        guard choice == 0 else { return }

        if locked {
            do {
                try karabiner.setLockMode(nil)
                completeUnlock(showHUD: false)
            } catch {
                showErrorAlert(title: "Unlock the keyboard first",
                               message: "PoohBooLock couldn't clear the lock: \(error.localizedDescription)")
                return
            }
        }

        do {
            let count = try KarabinerConfig.removeRules()
            if count > 0 {
                hud.show(title: "PoohBooLock Rule Removed",
                         subtitle: "\(count) rule\(count == 1 ? "" : "s") removed from Karabiner",
                         symbol: "trash.fill")
            } else {
                hud.show(title: "No Rule Found",
                         subtitle: "Nothing to remove",
                         symbol: "checkmark.circle.fill")
            }
        } catch {
            showErrorAlert(title: "Couldn't remove the Karabiner rule",
                           message: error.localizedDescription)
        }
    }

    @objc private func toggleLoginItemAction() {
        let enabling = !LoginItem.isEnabledForCurrentApp
        do {
            try LoginItem.setEnabled(enabling)
            updateStatusItem()
            hud.show(title: enabling ? "Launch at Login On" : "Launch at Login Off",
                     subtitle: enabling
                        ? "PoohBooLock will start with your Mac"
                        : "PoohBooLock won't start automatically",
                     symbol: enabling ? "checkmark.circle.fill" : "minus.circle.fill")
        } catch {
            showErrorAlert(title: "Couldn't update the login item",
                           message: error.localizedDescription)
        }
    }

    @objc private func revealBackupsAction() {
        ensureSupportDirectory()
        revealInFinder(AppInfo.backupsDirectory)
    }

    @objc private func revealLogAction() {
        ensureSupportDirectory()
        if !FileManager.default.fileExists(atPath: AppInfo.logFileURL.path) {
            pblLog("log opened from the menu")
        }
        revealInFinder(AppInfo.logFileURL)
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }

    // MARK: - Alerts

    private func showMissingKarabinerAlert() {
        let choice = showAlert(
            title: "Karabiner-Elements is required",
            message: "PoohBooLock blocks only the built-in keyboard by adding a rule to Karabiner-Elements, "
            + "but Karabiner-Elements (or its command-line tool) was not found.\n\n"
            + "Install Karabiner-Elements from karabiner-elements.pqrs.org, keep it running, then try again.",
            style: .warning,
            buttons: ["Open Download Page", "OK"])
        if choice == 0, let url = URL(string: "https://karabiner-elements.pqrs.org") {
            NSWorkspace.shared.open(url)
        }
    }

    private func showKarabinerNotRunningAlert() {
        let choice = showAlert(
            title: "Karabiner-Elements isn't running",
            message: "Start Karabiner-Elements, then click Lock again.\n\n"
            + "PoohBooLock can't block the built-in keyboard without it.",
            style: .warning,
            buttons: ["Open Karabiner-Elements", "OK"])
        if choice == 0 {
            karabiner.openKarabiner()
        }
    }

    // MARK: - Unlock notifications from Karabiner

    private func startStateWatcher() {
        stopStateWatcher()

        let fd = open(AppInfo.stateFileURL.path, O_EVTONLY)
        guard fd >= 0 else {
            pblLog("could not open the state file for watching")
            return
        }
        stateFileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .delete, .rename],
            queue: .main)

        source.setEventHandler { [weak self, weak source] in
            guard let self else { return }
            let flags = source?.data ?? []
            self.pollStateFile()
            if flags.contains(.delete) || flags.contains(.rename) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.startStateWatcher()
                }
            }
        }
        source.setCancelHandler { [weak self] in
            if let self, self.stateFileDescriptor == fd {
                self.stateFileDescriptor = -1
            }
            close(fd)
        }

        stateWatcher = source
        source.resume()
    }

    private func stopStateWatcher() {
        stateWatcher?.cancel()
        stateWatcher = nil
    }

    private func pollStateFile() {
        guard let content = try? String(contentsOf: AppInfo.stateFileURL, encoding: .utf8) else { return }
        let value = content.trimmingCharacters(in: .whitespacesAndNewlines)

        if value == "unlocked" {
            if locked {
                pblLog("external unlock detected (C + A + T)")
                completeUnlock(showHUD: true)
            }
            return
        }

        guard let mode = LockMode.fromStateValue(value) else { return }
        if locked {
            updateLockModeFromState(mode)
        } else {
            adoptExternalLock(mode: mode)
        }
    }

    /// The command line `--lock` / `--lock-all` mode (or another script)
    /// wrote a locked state. Follow along so the menu bar stays truthful.
    private func adoptExternalLock(mode: LockMode) {
        guard !locked, !lockInProgress else { return }
        guard karabiner.isInstalled, let profile = karabiner.runningProfileName() else { return }

        locked = true
        lockedMode = mode
        lockedProfileName = profile
        coreSignatureAtLock = karabiner.coreServiceSignature()
        startWatchdog()
        updateStatusItem()
        hud.show(title: mode.lockedTitle,
                 subtitle: mode.lockHUDSubtitle,
                 symbol: mode.statusSymbol)
        pblLog("adopted externally requested \(mode.rawValue) lock (profile \(profile))")
    }

    /// The lock is already held by Karabiner; an external caller only changed
    /// the mode (for example `--lock` while `--lock-all` was active).
    private func updateLockModeFromState(_ mode: LockMode) {
        guard locked, lockedMode != mode else { return }
        lockedMode = mode
        updateStatusItem()

        let subtitle = mode == .allKeyboards
            ? "External keyboards are locked too · C + A + T to unlock"
            : "External keyboards are usable again · C + A + T to unlock"
        hud.show(title: mode.lockedTitle,
                 subtitle: subtitle,
                 symbol: mode.statusSymbol)
        pblLog("lock mode changed externally to \(mode.rawValue)")
    }

    // MARK: - Watchdog

    private func startWatchdog() {
        stopWatchdog()
        let timer = Timer(timeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.watchdogTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdogTimer = timer
    }

    private func stopWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        watchdogBusy = false
    }

    private func watchdogTick() {
        guard locked, !watchdogBusy else { return }
        watchdogBusy = true
        pollStateFile()
        guard locked else {
            watchdogBusy = false
            return
        }

        let expectedProfile = lockedProfileName
        let expectedSignature = coreSignatureAtLock

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let profile = self.karabiner.runningProfileName(timeout: 2)
            let signature = self.karabiner.coreServiceSignature(timeout: 1.5)
            let rulePresent: Bool
            if let profile {
                rulePresent = KarabinerConfig.ruleIsInstalled(profileName: profile)
            } else {
                rulePresent = false
            }

            DispatchQueue.main.async {
                self.watchdogBusy = false
                guard self.locked else { return }

                guard let profile else {
                    self.releaseLock(reason: "Karabiner-Elements stopped responding")
                    return
                }
                if let expectedSignature, let signature, expectedSignature != signature {
                    self.releaseLock(reason: "Karabiner-Elements restarted")
                    return
                }
                if let expectedProfile, profile != expectedProfile {
                    try? self.karabiner.setLockMode(nil)
                    self.releaseLock(reason: "Karabiner profile changed to “\(profile)”")
                    return
                }
                if !rulePresent {
                    try? self.karabiner.setLockMode(nil)
                    self.releaseLock(reason: "The PoohBooLock rule was removed from Karabiner")
                }
            }
        }
    }
}
