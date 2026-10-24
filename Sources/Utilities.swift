import AppKit
import Darwin
import Foundation

// MARK: - App constants

enum AppInfo {
    static let name = "PoohBooLock"
    static let unlockCombo = "C + A + T"

    static var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"
    }

    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("PoohBooLock", isDirectory: true)
    }

    static var stateFileURL: URL { supportDirectory.appendingPathComponent("state") }
    static var logFileURL: URL { supportDirectory.appendingPathComponent("pooboolock.log") }
    static var backupsDirectory: URL { supportDirectory.appendingPathComponent("backups", isDirectory: true) }
}

// MARK: - Files & logging

func ensureSupportDirectory() {
    let fm = FileManager.default
    for url in [AppInfo.supportDirectory, AppInfo.backupsDirectory] {
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}

private let logQueue = DispatchQueue(label: "com.giraffe.pooboolock.log")

func pblLog(_ message: String) {
    NSLog("PoohBooLock: %@", message)
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    let line = "[\(formatter.string(from: Date()))] \(message)\n"

    logQueue.async {
        ensureSupportDirectory()
        guard let data = line.data(using: .utf8) else { return }
        let path = AppInfo.logFileURL.path
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil,
                                           attributes: [.posixPermissions: 0o600])
        }
        guard let handle = try? FileHandle(forWritingTo: AppInfo.logFileURL) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            // Logging must never break the app.
        }
    }
}

/// Writes a small state marker consumed by the menu bar app and by the
/// Karabiner unlock rule. Values used: "locked" / "unlocked".
func writeStateFile(_ value: String) {
    ensureSupportDirectory()
    do {
        // Deliberately non-atomic: a DispatchSource watches this file's inode.
        try (value + "\n").data(using: .utf8)?.write(to: AppInfo.stateFileURL)
    } catch {
        pblLog("could not write state file: \(error.localizedDescription)")
    }
}

// MARK: - Running helper processes

struct ProcessResult {
    let status: Int32
    let stdout: String
    let stderr: String
    let timedOut: Bool

    var ok: Bool { !timedOut && status == 0 }
}

@discardableResult
func runProcess(_ executable: String,
                _ arguments: [String],
                timeout: TimeInterval = 5,
                quiet: Bool = false) -> ProcessResult {
    guard FileManager.default.isExecutableFile(atPath: executable) else {
        return ProcessResult(status: -1, stdout: "",
                             stderr: "not found: \(executable)", timedOut: false)
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments

    let outPipe = Pipe()
    let errPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = errPipe

    let semaphore = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in semaphore.signal() }

    do {
        try process.run()
    } catch {
        return ProcessResult(status: -1, stdout: "", stderr: error.localizedDescription,
                             timedOut: false)
    }

    var timedOut = false
    if semaphore.wait(timeout: .now() + timeout) == .timedOut {
        timedOut = true
        process.terminate()
        if semaphore.wait(timeout: .now() + 0.4) == .timedOut {
            kill(process.processIdentifier, SIGKILL)
            _ = semaphore.wait(timeout: .now() + 0.5)
        }
    }
    process.waitUntilExit()

    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
    let stdout = String(data: outData, encoding: .utf8) ?? ""
    let stderr = String(data: errData, encoding: .utf8) ?? ""

    if !quiet && (timedOut || process.terminationStatus != 0 || !stderr.isEmpty) {
        let display = ([URL(fileURLWithPath: executable).lastPathComponent] + arguments)
            .joined(separator: " ")
        pblLog("process \(display) -> status \(process.terminationStatus)"
               + (timedOut ? " (timed out)" : "")
               + (stderr.isEmpty ? "" : " stderr: \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"))
    }

    return ProcessResult(status: process.terminationStatus, stdout: stdout,
                         stderr: stderr, timedOut: timedOut)
}

// MARK: - Alerts & Finder helpers

/// Shows a modal alert and returns the index of the clicked button (0-based).
@discardableResult
func showAlert(title: String,
               message: String,
               style: NSAlert.Style = .informational,
               buttons: [String] = ["OK"]) -> Int {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = style
    alert.icon = NSApp.applicationIconImage
    for button in buttons {
        alert.addButton(withTitle: button)
    }
    let response = alert.runModal()
    return response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
}

func showErrorAlert(title: String, message: String) {
    _ = showAlert(title: title, message: message, style: .warning, buttons: ["OK"])
}

func revealInFinder(_ url: URL) {
    let fm = FileManager.default
    if !fm.fileExists(atPath: url.path) {
        try? fm.createDirectory(at: url.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        fm.createFile(atPath: url.path, contents: Data())
    }
    NSWorkspace.shared.activateFileViewerSelecting([url])
}

func symbolImage(_ name: String, pointSize: CGFloat = 13) -> NSImage? {
    let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
    let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration)
    image?.isTemplate = true
    return image
}
