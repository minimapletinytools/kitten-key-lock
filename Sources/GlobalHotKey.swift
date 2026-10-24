import Carbon.HIToolbox
import Foundation

/// The Karabiner unlock rule emits Control+F20 after it clears the lock
/// variable. The app listens for that (permission-free) Carbon hot key and
/// updates its menu bar icon. F20 is not on a MacBook keyboard, so this acts
/// as a private one-way notification channel.
enum UnlockMarker {
    static let keyCode = UInt32(kVK_F20)
    static let modifiers = UInt32(controlKey)
}

final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var action: (() -> Void)?

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) -> Bool {
        unregister()
        self.action = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(GetApplicationEventTarget(),
                                                { (_, _, userData) -> OSStatus in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            hotKey.action?()
            return noErr
        },
                                                1,
                                                &eventType,
                                                selfPointer,
                                                &handlerRef)

        guard installStatus == noErr else {
            pblLog("InstallEventHandler failed: \(installStatus)")
            handlerRef = nil
            return false
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x50424C4B), id: 1) // 'PBLK'
        let status = RegisterEventHotKey(keyCode,
                                         modifiers,
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &hotKeyRef)
        guard status == noErr else {
            pblLog("RegisterEventHotKey failed: \(status)")
            if let handlerRef {
                RemoveEventHandler(handlerRef)
            }
            handlerRef = nil
            return false
        }

        pblLog("unlock-marker hotkey registered (Control+F20)")
        return true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }
}
