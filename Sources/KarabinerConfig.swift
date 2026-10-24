import Foundation

// MARK: - Errors

struct PoohBooLockError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// MARK: - Karabiner controller

/// Talk to Karabiner-Elements' command line tool and keep the lock state in
/// Karabiner's `manipulator_environment` variable `pooboolock_locked`.
final class KarabinerController {
    static let shared = KarabinerController()

    static let cliPath = "/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli"
    static let appPath = "/Applications/Karabiner-Elements.app"
    static let variableName = "pooboolock_locked"
    static let allKeyboardsVariableName = "pooboolock_all"
    static let sequenceFlagNames = ["pooboolock_c", "pooboolock_a", "pooboolock_t"]
    static let ruleMarker = "PoohBooLock: block the built-in keyboard while locked"

    var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: Self.cliPath)
    }

    /// Name of the currently selected Karabiner profile, or nil when
    /// Karabiner is not running / not installed.
    func runningProfileName(timeout: TimeInterval = 3) -> String? {
        guard isInstalled else { return nil }
        let result = runProcess(Self.cliPath,
                                ["--show-current-profile-name"],
                                timeout: timeout,
                                quiet: true)
        guard result.ok else { return nil }
        let name = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// PIDs of the Karabiner core service processes. Used to detect a
    /// Karabiner restart, which clears all variables (and therefore the lock).
    func coreServiceSignature(timeout: TimeInterval = 1.5) -> String? {
        let result = runProcess("/usr/bin/pgrep",
                                ["-x", "Karabiner-Core-Service"],
                                timeout: timeout,
                                quiet: true)
        guard result.ok else { return nil }
        let pids = result.stdout
            .split(whereSeparator: { $0 == "\n" || $0 == " " || $0 == "\t" })
            .map(String.init)
            .filter { !$0.isEmpty }
            .sorted()
        return pids.isEmpty ? nil : pids.joined(separator: ",")
    }

    /// mode == nil means "unlocked". `.builtInOnly` blocks only the built-in
    /// keyboard; `.allKeyboards` blocks every keyboard.
    func setLockMode(_ mode: LockMode?, timeout: TimeInterval = 4) throws {
        guard isInstalled else {
            throw PoohBooLockError("Karabiner-Elements is not installed (karabiner_cli was not found).")
        }
        var payload: [String: Int] = [
            Self.variableName: mode == nil ? 0 : 1,
            Self.allKeyboardsVariableName: mode == .allKeyboards ? 1 : 0
        ]
        for flag in Self.sequenceFlagNames {
            payload[flag] = 0
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            throw PoohBooLockError("Could not encode the Karabiner variables.")
        }
        let result = runProcess(Self.cliPath,
                                ["--set-variables", json],
                                timeout: timeout)
        if result.timedOut {
            throw PoohBooLockError("Karabiner-Elements did not respond (timed out).")
        }
        if result.status != 0 || result.stderr.lowercased().contains("error") {
            let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw PoohBooLockError(detail.isEmpty
                                   ? "karabiner_cli exited with status \(result.status)."
                                   : detail)
        }
    }

    func openKarabiner() {
        guard FileManager.default.fileExists(atPath: Self.appPath) else { return }
        _ = runProcess("/usr/bin/open", ["-a", Self.appPath], timeout: 3, quiet: true)
    }

    var configURL: URL {
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            let candidate = URL(fileURLWithPath: xdg)
                .appendingPathComponent("karabiner/karabiner.json")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/karabiner/karabiner.json")
    }
}

// MARK: - Karabiner configuration editing

enum KarabinerConfig {
    static var configURL: URL { KarabinerController.shared.configURL }

    static func loadRoot() throws -> [String: Any] {
        let url = configURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PoohBooLockError("Karabiner configuration was not found at \(url.path).")
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw PoohBooLockError("Could not read the Karabiner configuration: \(error.localizedDescription)")
        }
        do {
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw PoohBooLockError("The Karabiner configuration has an unexpected format.")
            }
            return root
        } catch let error as PoohBooLockError {
            throw error
        } catch {
            throw PoohBooLockError("The Karabiner configuration is not valid JSON: \(error.localizedDescription)")
        }
    }

    static func isOurRule(_ rule: [String: Any]) -> Bool {
        guard let description = rule["description"] as? String else { return false }
        return description.hasPrefix("PoohBooLock:")
    }

    static func profilesFrom(_ root: [String: Any]) throws -> [[String: Any]] {
        guard let profiles = root["profiles"] as? [[String: Any]], !profiles.isEmpty else {
            throw PoohBooLockError("The Karabiner configuration has no profiles.")
        }
        return profiles
    }

    static func profileIndex(in profiles: [[String: Any]], name: String?) -> Int {
        if let name, let index = profiles.firstIndex(where: { ($0["name"] as? String) == name }) {
            return index
        }
        if let index = profiles.firstIndex(where: { ($0["selected"] as? Bool) == true }) {
            return index
        }
        return 0
    }

    static func ruleIsInstalled(profileName: String?) -> Bool {
        do {
            let root = try loadRoot()
            let profiles = try profilesFrom(root)
            let index = profileIndex(in: profiles, name: profileName)
            let complex = profiles[index]["complex_modifications"] as? [String: Any]
            let rules = complex?["rules"] as? [[String: Any]] ?? []
            return rules.contains(where: isOurRule)
        } catch {
            return false
        }
    }

    /// Adds the PoohBooLock rule to the selected Karabiner profile.
    /// Returns true when the configuration was changed.
    @discardableResult
    static func ensureRule(profileName: String?) throws -> Bool {
        var root = try loadRoot()
        var profiles = try profilesFrom(root)
        let index = profileIndex(in: profiles, name: profileName)
        var profile = profiles[index]

        var complex = profile["complex_modifications"] as? [String: Any] ?? [:]
        var rules = complex["rules"] as? [[String: Any]] ?? []

        let desiredRule = try makeRule()
        let existingRules = rules.filter(isOurRule)
        if existingRules.count == 1, jsonEqual(existingRules[0], desiredRule) {
            return false
        }

        // Replace old/incomplete PoohBooLock rules (for example after an app
        // update changed the unlock command).
        rules.removeAll(where: isOurRule)
        rules.insert(desiredRule, at: 0)
        complex["rules"] = rules
        profile["complex_modifications"] = complex
        profiles[index] = profile
        root["profiles"] = profiles

        try write(root)

        // Read the file back and make sure the rule really landed.
        let profileName = profiles[index]["name"] as? String
        guard ruleIsInstalled(profileName: profileName) else {
            throw PoohBooLockError("The PoohBooLock rule could not be verified in the Karabiner configuration.")
        }
        return true
    }

    /// Removes every PoohBooLock rule from every profile.
    /// Returns the number of removed rules.
    @discardableResult
    static func removeRules() throws -> Int {
        var root = try loadRoot()
        var profiles = try profilesFrom(root)
        var removed = 0

        for index in profiles.indices {
            guard var complex = profiles[index]["complex_modifications"] as? [String: Any],
                  var rules = complex["rules"] as? [[String: Any]] else { continue }
            let before = rules.count
            rules.removeAll(where: isOurRule)
            if rules.count != before {
                removed += before - rules.count
                complex["rules"] = rules
                profiles[index]["complex_modifications"] = complex
            }
        }

        if removed > 0 {
            root["profiles"] = profiles
            try write(root)
        }
        return removed
    }

    // MARK: Writing

    private static func jsonEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        guard let left = try? JSONSerialization.data(withJSONObject: lhs,
                                                       options: [.sortedKeys]),
              let right = try? JSONSerialization.data(withJSONObject: rhs,
                                                        options: [.sortedKeys]) else {
            return false
        }
        return left == right
    }

    private static func write(_ root: [String: Any]) throws {
        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: root,
                                              options: [.prettyPrinted, .withoutEscapingSlashes])
        } catch {
            throw PoohBooLockError("Could not serialize the Karabiner configuration: \(error.localizedDescription)")
        }

        var output = data
        if output.last != 0x0A { output.append(0x0A) }

        try backupConfiguration()

        let url = configURL
        do {
            try output.write(to: url, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                  ofItemAtPath: url.path)
        } catch {
            throw PoohBooLockError("Could not write the Karabiner configuration: \(error.localizedDescription)")
        }
        pblLog("wrote Karabiner configuration (\(output.count) bytes)")
    }

    private static func backupConfiguration() throws {
        let fm = FileManager.default
        let backups = AppInfo.backupsDirectory
        do {
            try fm.createDirectory(at: backups, withIntermediateDirectories: true)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
            let base = "karabiner-\(formatter.string(from: Date()))"
            var destination = backups.appendingPathComponent("\(base).json")
            var suffix = 1
            while fm.fileExists(atPath: destination.path) {
                destination = backups.appendingPathComponent("\(base)-\(suffix).json")
                suffix += 1
            }
            try fm.copyItem(at: configURL, to: destination)
            pblLog("backed up Karabiner configuration to \(destination.path)")

            if let files = try? fm.contentsOfDirectory(at: backups,
                                                       includingPropertiesForKeys: nil) {
                let old = files
                    .filter { $0.lastPathComponent.hasPrefix("karabiner-") }
                    .sorted { $0.lastPathComponent > $1.lastPathComponent }
                for url in old.dropFirst(30) {
                    try? fm.removeItem(at: url)
                }
            }
        } catch {
            throw PoohBooLockError("Could not back up the Karabiner configuration: \(error.localizedDescription)")
        }
    }

    // MARK: The rule

    static func makeRule() throws -> [String: Any] {
        let lockCondition: [String: Any] = [
            "type": "variable_if",
            "name": KarabinerController.variableName,
            "value": 1
        ]
        let allKeyboardsCondition: [String: Any] = [
            "type": "variable_if",
            "name": KarabinerController.allKeyboardsVariableName,
            "value": 1
        ]
        let builtInOnlyCondition: [String: Any] = [
            "type": "variable_unless",
            "name": KarabinerController.allKeyboardsVariableName,
            "value": 1
        ]
        let builtInCondition: [String: Any] = [
            "type": "device_if",
            "identifiers": [["is_built_in_keyboard": true]]
        ]
        let externalCondition: [String: Any] = [
            "type": "device_unless",
            "identifiers": [["is_built_in_keyboard": true]]
        ]

        let baseConditions: [[String: Any]] = [lockCondition, builtInCondition]
        let allExternalConditions: [[String: Any]] = [
            lockCondition, allKeyboardsCondition, externalCondition
        ]
        let externalChordConditions: [[String: Any]] = [
            lockCondition, builtInOnlyCondition, externalCondition
        ]
        let allConditions: [[String: Any]] = [lockCondition, allKeyboardsCondition]

        func letterFrom(_ key: String) -> [String: Any] {
            [
                "key_code": key,
                "modifiers": ["optional": ["caps_lock"]] as [String: Any]
            ]
        }

        let clearFlags: [[String: Any]] = KarabinerController.sequenceFlagNames.map { name -> [String: Any] in
            ["set_variable": ["name": name, "value": 0] as [String: Any]]
        }

        // Control+F20 is not a physical MacBook key. The menu bar app listens
        // for it as a permission-free "the unlock rule fired" marker.
        let marker: [String: Any] = [
            "key_code": "f20",
            "modifiers": ["control"]
        ]
        let unlockActions: [[String: Any]] = [
            ["set_variable": ["name": KarabinerController.variableName, "value": 0] as [String: Any]],
            ["set_variable": ["name": KarabinerController.allKeyboardsVariableName, "value": 0] as [String: Any]]
        ] + clearFlags + [marker]

        let letters: [(key: String, flag: String)] = [
            ("c", "pooboolock_c"),
            ("a", "pooboolock_a"),
            ("t", "pooboolock_t")
        ]

        var manipulators: [[String: Any]] = []

        func appendSequentialUnlock(conditions: [[String: Any]]) {
            // The letter that completes C + A + T unlocks. The other two
            // flags must already be set; conditions are evaluated before the
            // action, so the order of the letters does not matter.
            for letter in letters {
                var letterConditions = conditions
                for other in letters where other.flag != letter.flag {
                    letterConditions.append([
                        "type": "variable_if",
                        "name": other.flag,
                        "value": 1
                    ])
                }
                manipulators.append([
                    "type": "basic",
                    "from": letterFrom(letter.key),
                    "to": unlockActions,
                    "conditions": letterConditions
                ])
            }

            // Remember the first two letters and swallow them.
            for letter in letters {
                manipulators.append([
                    "type": "basic",
                    "from": letterFrom(letter.key),
                    "to": [["set_variable": ["name": letter.flag, "value": 1] as [String: Any]]],
                    "conditions": conditions
                ])
            }
        }

        // 1. Sequential C/A/T on the built-in keyboard works in both modes.
        appendSequentialUnlock(conditions: baseConditions)

        // 2. A deliberate simultaneous C+A+T chord on an external keyboard
        //    while in built-in-only mode. Individual keys are not captured,
        //    so normal typing on the external keyboard is left untouched.
        manipulators.append([
            "type": "basic",
            "from": [
                "simultaneous": [
                    ["key_code": "c"],
                    ["key_code": "a"],
                    ["key_code": "t"]
                ],
                "modifiers": ["optional": ["caps_lock"]] as [String: Any]
            ] as [String: Any],
            "to": unlockActions,
            "conditions": externalChordConditions,
            "parameters": ["basic.simultaneous_threshold_milliseconds": 150]
        ])

        // 3. In all-keyboards mode the external keyboard is blocked anyway,
        //    so a normal sequential C/A/T from it unlocks too.
        appendSequentialUnlock(conditions: allExternalConditions)

        // 4. Every other key from the built-in keyboard is swallowed and
        //    clears the partial C/A/T sequence. "optional: any" is important:
        //    it also catches Shift/Cmd/Option/Control + key combos.
        manipulators.append([
            "type": "basic",
            "from": [
                "any": "key_code",
                "modifiers": ["optional": ["any"]] as [String: Any]
            ],
            "to": clearFlags,
            "conditions": baseConditions
        ])
        manipulators.append([
            "type": "basic",
            "from": [
                "any": "consumer_key_code",
                "modifiers": ["optional": ["any"]] as [String: Any]
            ],
            "conditions": baseConditions
        ])

        // 5. All-keyboards mode: suppress every keyboard; no device_if.
        manipulators.append([
            "type": "basic",
            "from": [
                "any": "key_code",
                "modifiers": ["optional": ["any"]] as [String: Any]
            ],
            "to": clearFlags,
            "conditions": allConditions
        ])
        manipulators.append([
            "type": "basic",
            "from": [
                "any": "consumer_key_code",
                "modifiers": ["optional": ["any"]] as [String: Any]
            ],
            "conditions": allConditions
        ])

        return [
            "description": KarabinerController.ruleMarker,
            "manipulators": manipulators
        ]
    }

}
