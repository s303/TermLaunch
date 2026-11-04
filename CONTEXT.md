# TermLaunch

A macOS-only terminal that stays resident in the background and drops down on a global hotkey.

## Language

**Dropdown**:
The single borderless window anchored to a screen edge. It fades in when the Activation key is pressed and fades out when dismissed, including whenever it loses focus. Its size is a configurable fraction of the screen, 50% by default.
_Avoid_: Quake window, popup, panel

**Activation key**:
The main global hotkey (commands may add their own, see Command hotkey). Pressing it shows the Dropdown if hidden and hides it if visible. Appearing and disappearing is a fade, with a configurable duration.

**Command key**:
A key bound to a configured CLI command. Pressing it right after the Activation key opens a Tab running that command in the Dropdown.

**Command hotkey**:
An optional global hotkey on a command (`hotkey = "f2"`). Pressing it from anywhere shows the Dropdown and opens or focuses that command's Command Tab; pressing it while that Tab is showing hides the Dropdown.

**Chord window**:
The configurable time after the Activation key shows the Dropdown during which a Command key is recognised. A Command key is a single key. Keys typed during the window are held back from the terminal; when the window ends without a Command key, the held keys are sent to the terminal as input.

**Tab**:
One terminal inside the Dropdown. The Dropdown holds one or more Tabs, and one is active at a time.
_Avoid_: Session, pane

**Command Tab**:
A Tab running the command bound to a Command key. There is at most one per Command key: pressing that Command key again focuses the existing Command Tab instead of opening a second one. It survives the Dropdown being hidden. When its command exits successfully the Tab closes and the Dropdown hides; on failure the Tab stays showing the output until a keypress.

**Launcher Tab**:
A Command Tab for a command with `builtin = "launcher"` instead of `run`. It is not a terminal: a search field at the bottom with results growing upward, the best match nearest the field. Enter runs the selected result (open the app, copy the calculation) and Esc cancels; both close the Tab like a command that exited successfully. Its history is shared with the `oa` CLI.

**Provider**:
A compiled-in source of Launcher Tab results: apps (Spotlight, fuzzy match weighted by frecency) and the calculator. Every provider sees every query and returns no results when it doesn't apply; results are grouped by provider, calculator first. See [ADR 0003](docs/adr/0003-builtin-launcher-providers.md).
_Avoid_: Plugin

**Shell Tab**:
A Tab running the default shell. It is what appears when the Dropdown is shown without a Command key. There can be many. A Shell Tab closes when its shell exits; if it was the last Tab, the Dropdown hides and a fresh Shell Tab is created on the next show.

**Window mode**:
TermLaunch can also run as a normal window, entered and left by the Window hotkey (`window` under `[hotkeys]` in the config, no default). The Tabs are the same Tabs and sessions as in the Dropdown, reparented between the two. While in Window mode the app has a Dock icon and appears in ⌘Tab; leaving Window mode removes both. The Window is freely resizable, starts at the Dropdown's grid size centred on the screen, and its frame is remembered for the app session.
_Avoid_: Detached, pop-out

**Window hotkey**:
Toggles between the Dropdown and Window mode, keeping all Tabs. Closing the Window (red button, ⌘W on the last Tab, ⌘Q) also leaves Window mode and keeps the Tabs; the Activation key then shows the Dropdown. Minimising the Window stays in Window mode. Quitting is only in the menu-bar item.

**Temporary console**:
In Window mode, when the Window is not the key window (behind other apps or minimised), the Activation key or a Command hotkey shows the Dropdown with the same Tabs and hides the Window meanwhile. Dismissing it (same key, or losing focus) restores the Window to its previous frame, z-order and minimised state without taking focus. The Dock icon stays throughout. The Chord window also applies in the Window, started silently by the Activation key.

**Window mode key rules**:
- Activation key while the Window is key: opens a Chord window in the Window with no Dropdown; a Command key within it runs its command in the Window, any other key goes to the terminal as usual.
- Command hotkey while the Window is key: opens or focuses that Command Tab in the Window; pressing it again does nothing.
- ⌘T, ⌘W, ⌘⇧[ / ⌘⇧], ⌘1–9 work through the app menu bar. ⌘Q is "Close Window" and leaves Window mode; "Quit TermLaunch" is listed beside it without a shortcut. Settings… (⌘,) opens the config file in the default app, like the menu-bar item. The Commands menu shows each command's `hotkey` as its key equivalent (display only, the global hotkey fires) or "Activation key then key" for chord-only commands.
- A command's optional `name` replaces its label in the Commands menu and pins its Tab title (the terminal's own title updates are ignored).
- A Command Tab that finishes successfully closes only that Tab in the Window; the Window stays.
