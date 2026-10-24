import Darwin
import Foundation

/// A tiny per-user LaunchAgent that re-opens the app at login.
/// (Using a LaunchAgent keeps the app ad-hoc-signable; SMAppService would
/// require a Developer ID in many setups.)
enum LoginItem {
    static let label = "com.giraffe.pooboolock.login"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabledForCurrentApp: Bool {
        guard let data = try? Data(contentsOf: plistURL),
              let object = try? PropertyListSerialization.propertyList(from: data,
                                                                        options: [],
                                                                        format: nil),
              let plist = object as? [String: Any],
              let arguments = plist["ProgramArguments"] as? [String],
              let dashA = arguments.firstIndex(of: "-a"),
              dashA + 1 < arguments.count else {
            return FileManager.default.fileExists(atPath: plistURL.path)
        }

        let configured = URL(fileURLWithPath: arguments[dashA + 1])
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let current = Bundle.main.bundleURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
        return configured == current
    }

    static func setEnabled(_ enabled: Bool) throws {
        let fm = FileManager.default
        let domain = "gui/\(getuid())"

        if enabled {
            let directory = plistURL.deletingLastPathComponent()
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)

            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": ["/usr/bin/open", "-a", Bundle.main.bundlePath],
                "RunAtLoad": true,
                "ProcessType": "Interactive",
                "LimitLoadToSessionType": "Aqua"
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: plist,
                                                          format: .xml,
                                                          options: 0)
            try data.write(to: plistURL, options: [.atomic])

            _ = runProcess("/bin/launchctl", ["bootstrap", domain, plistURL.path], timeout: 3,
                           quiet: true)
            _ = runProcess("/bin/launchctl", ["enable", "\(domain)/\(label)"], timeout: 3,
                           quiet: true)
        } else {
            _ = runProcess("/bin/launchctl", ["bootout", "\(domain)/\(label)"], timeout: 3,
                           quiet: true)
            if fm.fileExists(atPath: plistURL.path) {
                try fm.removeItem(at: plistURL)
            }
        }
    }
}
