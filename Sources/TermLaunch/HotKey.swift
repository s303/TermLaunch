import Carbon.HIToolbox

/// Global hotkey via Carbon `RegisterEventHotKey`, which needs no
/// Accessibility or Input Monitoring permission.
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void
    private let hotKeyID: UInt32

    /// `keyCode` is a `kVK_*` virtual key code; `modifiers` are Carbon flags
    /// (`controlKey`, `optionKey`, `cmdKey`, `shiftKey`).
    init?(id hotKeyID: UInt32 = 1, keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action
        self.hotKeyID = hotKeyID

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData, let event else { return noErr }
                let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
                var pressed = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
                // Every HotKey sees every hotkey event; only react to our own.
                guard status == noErr, pressed.id == hotKey.hotKeyID else { return OSStatus(eventNotHandledErr) }
                DispatchQueue.main.async { hotKey.action() }
                return noErr
            },
            1, &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        guard status == noErr else { return nil }

        let id = EventHotKeyID(signature: OSType(0x544C4B59), id: hotKeyID) // 'TLKY'
        let reg = RegisterEventHotKey(
            UInt32(keyCode), UInt32(modifiers), id,
            GetApplicationEventTarget(), 0, &ref
        )
        guard reg == noErr else {
            if let handlerRef { RemoveEventHandler(handlerRef) }
            return nil
        }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
