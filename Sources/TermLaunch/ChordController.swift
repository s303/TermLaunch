import AppKit

/// Owns a Chord window's `ChordKeys`, its duration and its timer. Shared by the Dropdown
/// and the Window so both behave identically; holds no window references.
final class ChordController {
    /// Runs the closure after the delay and returns a cancel function. Injectable for tests.
    typealias Scheduler = (TimeInterval, @escaping () -> Void) -> () -> Void

    static let timerScheduler: Scheduler = { delay, fire in
        let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in fire() }
        return { timer.invalidate() }
    }

    private(set) var keys = ChordKeys()
    private(set) var duration: TimeInterval = 0.3
    private var cancelTimer: (() -> Void)?
    private let schedule: Scheduler

    init(schedule: @escaping Scheduler = ChordController.timerScheduler) {
        self.schedule = schedule
    }

    var isActive: Bool { keys.isActive }

    func apply(commandKeys: Set<String>, activationKey: KeySpec?, chordWindow: TimeInterval) {
        keys.commandKeys = commandKeys
        keys.activationKey = activationKey
        duration = chordWindow
    }

    func apply(_ config: Config) {
        apply(commandKeys: Set(config.commands.compactMap(\.key)),
              activationKey: KeySpec.parse(config.activation),
              chordWindow: TimeInterval(config.chordWindowMs) / 1000)
    }

    /// Opens a Chord window, ending any one still open.
    func begin() {
        end()
        guard duration > 0, keys.begin() else { return }
        cancelTimer = schedule(duration) { [weak self] in
            self?.cancelTimer = nil
            self?.keys.end()
        }
    }

    func end() {
        cancelTimer?()
        cancelTimer = nil
        keys.end()
    }

    /// Ends the window and forgets held keys, whose keyUps will not arrive.
    func reset() {
        end()
        keys.reset()
    }

    func handle(_ event: NSEvent) -> ChordKeys.Result {
        handle(type: event.type, keyCode: event.keyCode, modifiers: event.modifierFlags)
    }

    func handle(type: NSEvent.EventType, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> ChordKeys.Result {
        let result: ChordKeys.Result
        switch type {
        case .keyDown: result = keys.keyDown(keyCode: keyCode, modifiers: modifiers)
        case .keyUp: result = keys.keyUp(keyCode: keyCode)
        default: result = .pass
        }
        if !keys.isActive { cancelTimer?(); cancelTimer = nil }
        return result
    }
}
