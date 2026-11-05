/// Decisions for where the Tabs are shown: the Dropdown, or Window mode with
/// its Temporary console. Pure, so the rules live in one tested place.
enum Presentation {
    struct State {
        var windowMode: Bool
        /// The Dropdown panel is on screen (in Window mode: the Temporary console).
        var consoleShown: Bool
        /// The Window is the key window, i.e. visible and active.
        var windowIsKey: Bool
    }

    enum Action: Equatable {
        case showConsole, hideConsole
        /// Window mode, Window active: open or focus the Tab in the Window.
        case useWindow
        /// Window mode, Window active: the next Command key runs in the Window.
        case windowChord
        case ignore
        case enterWindowMode, leaveWindowMode
    }

    static func activation(_ s: State) -> Action {
        if s.consoleShown { return .hideConsole }
        if s.windowMode && s.windowIsKey { return .windowChord }
        return .showConsole
    }

    /// `commandTabActive`: the console is showing this hotkey's Command Tab.
    static func commandHotkey(_ s: State, commandTabActive: Bool) -> Action {
        if s.consoleShown { return commandTabActive ? .hideConsole : .showConsole }
        if s.windowMode && s.windowIsKey { return .useWindow }
        return .showConsole
    }

    /// Only while the Dropdown or the Window is in front; otherwise the key belongs to another app.
    static func windowHotkey(_ s: State) -> Action {
        guard s.consoleShown || (s.windowMode && s.windowIsKey) else { return .ignore }
        return s.windowMode ? .leaveWindowMode : .enterWindowMode
    }
}
