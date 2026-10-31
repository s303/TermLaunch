# Window mode reparents one shared content view

TermLaunch gains a normal-window presentation alongside the Dropdown. The Tabs and their ghostty surfaces live in a single `DropdownContentView`, which is reparented between the Dropdown panel and an `NSWindow`, so sessions survive every switch. The two presentations are never visible at once: the Window is hidden while a temporary console is up and restored afterwards.

The Window hotkey is the only way into Window mode, and closing the Window (including ⌘Q) is the way out; neither kills Tabs. Window mode owns the Dock icon: the activation policy is `.regular` while in it and `.accessory` otherwise, including during a temporary console.

## Considered Options

- A second set of Tabs for the window: simpler views, but sessions would not carry over, which is the whole point.
- Window hotkey only opens/focuses the window: leaves no way to return to the Dropdown without closing.
- ⌘Q quits in Window mode: rejected, quitting stays in the menu-bar item so a stray ⌘Q cannot kill sessions.
