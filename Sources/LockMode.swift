import Foundation

/// The two ways PoohBooLock can be armed.
enum LockMode: String, CaseIterable {
    /// Only the MacBook's built-in keyboard is suppressed. External
    /// keyboards and the trackpad keep working.
    case builtInOnly

    /// Every keyboard is suppressed, including USB/Bluetooth ones.
    case allKeyboards

    var stateValue: String {
        switch self {
        case .builtInOnly: return "locked-builtin"
        case .allKeyboards: return "locked-all"
        }
    }

    var displayName: String {
        switch self {
        case .builtInOnly: return "Built-in Keyboard"
        case .allKeyboards: return "All Keyboards"
        }
    }

    var lockedTitle: String {
        "\(displayName) Locked"
    }

    /// Status item symbol for this mode.
    var statusSymbol: String {
        switch self {
        case .builtInOnly: return "cat.fill"
        case .allKeyboards: return "cat.circle.fill"
        }
    }

    /// Menu item symbol for choosing this mode.
    var menuSymbol: String {
        switch self {
        case .builtInOnly: return "laptopcomputer"
        case .allKeyboards: return "keyboard"
        }
    }

    var lockHUDSubtitle: String {
        switch self {
        case .builtInOnly: return "Press C + A + T to unlock · external keyboards work"
        case .allKeyboards: return "Press C + A + T on either keyboard to unlock"
        }
    }

    static func fromStateValue(_ value: String) -> LockMode? {
        switch value {
        case "locked", "locked-builtin": return .builtInOnly
        case "locked-all": return .allKeyboards
        default: return nil
        }
    }
}
