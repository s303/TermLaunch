# TermLaunch

A macOS-only terminal that stays resident in the background and drops down on a global hotkey.

## Language

**Dropdown**:
The single borderless window anchored to a screen edge. It fades in when the Activation key is pressed and fades out when dismissed, including whenever it loses focus. Its size is a configurable fraction of the screen, 50% by default.
_Avoid_: Quake window, popup, panel

**Activation key**:
The single global hotkey. Pressing it shows the Dropdown if hidden and hides it if visible. Appearing and disappearing is a fade, with a configurable duration.

**Command key**:
A key bound to a configured CLI command. Pressing it right after the Activation key opens a Tab running that command in the Dropdown.

**Chord window**:
The configurable time after the Activation key shows the Dropdown during which a Command key is recognised. A Command key is a single key. Keys typed during the window are held back from the terminal; when the window ends without a Command key, the held keys are sent to the terminal as input.

**Tab**:
One terminal inside the Dropdown. The Dropdown holds one or more Tabs, and one is active at a time.
_Avoid_: Session, pane

**Command Tab**:
A Tab running the command bound to a Command key. There is at most one per Command key: pressing that Command key again focuses the existing Command Tab instead of opening a second one. It survives the Dropdown being hidden. When its command exits successfully the Tab closes and the Dropdown hides; on failure the Tab stays showing the output until a keypress.

**Shell Tab**:
A Tab running the default shell. It is what appears when the Dropdown is shown without a Command key. There can be many. A Shell Tab closes when its shell exits; if it was the last Tab, the Dropdown hides and a fresh Shell Tab is created on the next show.
