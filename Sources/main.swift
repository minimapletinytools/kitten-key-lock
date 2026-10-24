import AppKit
import Foundation

// MARK: - Small command line interface (also handy for debugging / install scripts)

enum CommandLineTool {
    static let usage = """
    PoohBooLock — lock the MacBook's built-in keyboard from the menu bar.

    Usage:
      PoohBooLock                     Start the menu bar app
      PoohBooLock --status            Print status information
      PoohBooLock --self-test         Check Karabiner integration
      PoohBooLock --install-rule      Add the PoohBooLock rule to the active Karabiner profile
      PoohBooLock --remove-rule       Remove PoohBooLock rules from all Karabiner profiles
      PoohBooLock --lock              Lock the built-in keyboard only (for testing)
      PoohBooLock --lock-all          Lock all keyboards, built-in and external (for testing)
      PoohBooLock --unlock            Unlock all keyboards
      PoohBooLock --help              Show this help

    Unlock at any time by pressing C, A and T on the built-in keyboard
    (together or in quick succession, in any order).
    """

    @discardableResult
    static func run(_ arguments: [String]) -> Bool {
        guard let command = arguments.first else { return false }

        ensureSupportDirectory()
        let karabiner = KarabinerController.shared

        switch command {
        case "--help", "-h":
            print(usage)
            exit(0)

        case "--version":
            print(AppInfo.version)
            exit(0)

        case "--status":
            printStatus(karabiner)
            exit(0)

        case "--self-test":
            selfTest(karabiner)
            exit(0)

        case "--install-rule":
            do {
                guard karabiner.isInstalled else {
                    print("error: Karabiner-Elements is not installed")
                    exit(1)
                }
                guard let profile = karabiner.runningProfileName() else {
                    print("error: Karabiner-Elements is not running")
                    exit(1)
                }
                let inserted = try KarabinerConfig.ensureRule(profileName: profile)
                print(inserted
                      ? "installed PoohBooLock rule in profile “\(profile)”"
                      : "PoohBooLock rule already present in profile “\(profile)”")
                exit(0)
            } catch {
                print("error: \(error.localizedDescription)")
                exit(1)
            }

        case "--remove-rule":
            do {
                let count = try KarabinerConfig.removeRules()
                print("removed \(count) PoohBooLock rule\(count == 1 ? "" : "s")")
                exit(0)
            } catch {
                print("error: \(error.localizedDescription)")
                exit(1)
            }

        case "--lock":
            lock(mode: .builtInOnly, karabiner: karabiner)

        case "--lock-all":
            lock(mode: .allKeyboards, karabiner: karabiner)

        case "--unlock":
            do {
                guard karabiner.isInstalled else {
                    print("error: Karabiner-Elements is not installed")
                    exit(1)
                }
                try karabiner.setLockMode(nil)
                writeStateFile("unlocked")
                print("unlocked")
                exit(0)
            } catch {
                print("error: \(error.localizedDescription)")
                exit(1)
            }

        default:
            print("unknown option: \(command)\n")
            print(usage)
            exit(2)
        }
    }

    private static func lock(mode: LockMode, karabiner: KarabinerController) -> Never {
        do {
            guard karabiner.isInstalled else {
                print("error: Karabiner-Elements is not installed")
                exit(1)
            }
            guard let profile = karabiner.runningProfileName() else {
                print("error: Karabiner-Elements is not running")
                exit(1)
            }
            let inserted = try KarabinerConfig.ensureRule(profileName: profile)
            if inserted {
                Thread.sleep(forTimeInterval: 0.7)
            }
            try karabiner.setLockMode(mode)
            writeStateFile(mode.stateValue)

            let target = mode == .allKeyboards ? "all keyboards" : "the built-in keyboard"
            print("locked \(target) (profile “\(profile)”) — unlock with C + A + T")
            exit(0)
        } catch {
            print("error: \(error.localizedDescription)")
            exit(1)
        }
    }

    private static func printStatus(_ karabiner: KarabinerController) {
        let profile = karabiner.runningProfileName()
        let state = (try? String(contentsOf: AppInfo.stateFileURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "<none>"
        print("PoohBooLock \(AppInfo.version)")
        print("support directory:  \(AppInfo.supportDirectory.path)")
        print("log:                \(AppInfo.logFileURL.path)")
        print("state file:         \(AppInfo.stateFileURL.path) (\(state))")
        print("karabiner installed:\(karabiner.isInstalled ? " yes" : " no")")
        print("karabiner cli:      \(KarabinerController.cliPath)")
        print("karabiner config:   \(KarabinerConfig.configURL.path)")
        print("active profile:     \(profile ?? "<not running>")")
        print("core service:       \(karabiner.coreServiceSignature() ?? "<not running>")")
        if let profile {
            print("rule installed:     \(KarabinerConfig.ruleIsInstalled(profileName: profile) ? "yes" : "no")")
        } else {
            print("rule installed:     unknown (Karabiner is not running)")
        }
    }

    private static func selfTest(_ karabiner: KarabinerController) {
        print("== PoohBooLock self-test ==")
        printStatus(karabiner)
        print("--")

        var failures = 0

        if !karabiner.isInstalled {
            print("FAIL: Karabiner-Elements CLI not found")
            failures += 1
        } else if karabiner.runningProfileName() == nil {
            print("FAIL: Karabiner-Elements is not running")
            failures += 1
        } else {
            print("OK: Karabiner-Elements is running")
        }

        do {
            let root = try KarabinerConfig.loadRoot()
            let profiles = try KarabinerConfig.profilesFrom(root)
            print("OK: Karabiner config parses (\(profiles.count) profile\(profiles.count == 1 ? "" : "s"))")
        } catch {
            print("FAIL: Karabiner config: \(error.localizedDescription)")
            failures += 1
        }

        do {
            try karabiner.setLockMode(nil)
            writeStateFile("unlocked")
            print("OK: can write the lock variables (set to unlocked)")
        } catch {
            print("FAIL: lock variable: \(error.localizedDescription)")
            failures += 1
        }

        if let profile = karabiner.runningProfileName(), !KarabinerConfig.ruleIsInstalled(profileName: profile) {
            print("NOTE: the PoohBooLock rule is not installed in the active profile yet "
                  + "(it is installed automatically on first lock)")
        }

        print("--")
        print(failures == 0 ? "RESULT: OK" : "RESULT: \(failures) problem(s)")
        exit(failures == 0 ? 0 : 1)
    }
}

// MARK: - Entry point

let commandLineArguments = Array(CommandLine.arguments.dropFirst())
if let first = commandLineArguments.first, first.hasPrefix("--") || first == "-h" {
    CommandLineTool.run(commandLineArguments)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
