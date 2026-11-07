import AppKit

/// Key decisions for the Chord window, shared by the Dropdown and the Window.
/// Pure, so the rules are tested; the owner keeps the timer and calls `end()` when it fires.
struct ChordKeys {
    enum Result: Equatable {
        /// Deliver the key to the terminal as usual.
        case pass
        /// Drop the key.
        case swallow
        /// Drop the key and run this Command key's command.
        case command(String)
    }

    var commandKeys: Set<String> = []
    /// The Activation key. When the app is already active (the Window is key), its keyDown
    /// reaches the window as well, after the Carbon hotkey has started the Chord window.
    var activationKey: KeySpec?
    private(set) var isActive = false
    private var swallowedKeyCodes = Set<UInt16>()

    /// Starts a Chord window; false when there is nothing to wait for.
    mutating func begin() -> Bool {
        isActive = !commandKeys.isEmpty
        return isActive
    }

    mutating func end() { isActive = false }

    /// Ends the Chord window and forgets held keys, whose keyUps will not arrive.
    mutating func reset() {
        isActive = false
        swallowedKeyCodes.removeAll()
    }

    mutating func keyDown(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Result {
        // Auto-repeat of a Command key that already ran its command.
        if swallowedKeyCodes.contains(keyCode) { return .swallow }
        // Already handled by the global hotkey; must not end the Chord window it started.
        if activationKey?.matches(keyCode: keyCode, modifiers: modifiers) == true { return .swallow }
        guard isActive else { return .pass }
        isActive = false
        // Match the physical key, like the Activation key, so non-US layouts work.
        guard modifiers.isDisjoint(with: [.command, .control, .option]),
              let key = KeySpec.name(forKeyCode: keyCode), commandKeys.contains(key)
        else { return .pass }
        swallowedKeyCodes.insert(keyCode)
        return .command(key)
    }

    mutating func keyUp(keyCode: UInt16) -> Result {
        swallowedKeyCodes.remove(keyCode) != nil ? .swallow : .pass
    }
}
