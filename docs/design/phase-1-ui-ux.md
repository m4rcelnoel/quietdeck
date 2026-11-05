# QuietDeck: UI/UX design (Phase 1, approved)

## Context

QuietDeck is a native macOS app that controls headphones directly over Bluetooth, with Bose QC Ultra Headphones 2nd Gen as the first target and a vendor-neutral core. This is the approved Phase 1 UI/UX design.


## Findings that shaped the design

> Update: later research answered several of these open points. The current protocol status is in [the implementation plan](../plan/phase-2-implementation-plan.md).

From a full read of `docs/PROTOCOLO-BMAP.md`, the repo README and ancbuddy.com:

| Finding | Design consequence |
|---|---|
| The reference has **no source listing, source switching or multipoint commands**. A competing product does show and switch sources, so a path very likely exists, but it is unknown to us. | Sources is designed in two tiers: full, and a degraded tier that still works (see Flow C). Discovery runs through the Protocol Console. |
| The reference **does not read mode, ANC, immersion or EQ from hardware**, only battery. Your spec requires reconciliation on connect. | Every control has an "unknown" state until a read succeeds. The GET commands are unverified and go in the Phase 2 protocol map as unknown. |
| The reference always sends `wind = 0` in `[31.10]`. Wind Block has **never been exercised**. | Wind Block is a capability that may turn out unavailable. The layout must look complete without it. |
| Manual changes to noise or immersion leave the preset. | A visible "Custom" state, with no mode selected (the reference calls this MANUAL). |
| Transactions take time: mode then 750 ms, then 250 ms steps; 8 s timeout. | Controls update optimistically, show a quiet pending state, and roll back with an inline message on failure. |
| Whether two Macs can hold a BMAP RFCOMM session on the same headset at once is unknown. | Handoff never assumes both Macs have live control. The remote Mac is shown from Bonjour state, not from the headset. |

## Information architecture

```
Menu bar extra (primary daily surface)
  Header: device, connection, battery
  Modes
  Noise control (if supported)
  Audio source + send to other Mac
  Footer: open app, settings

Main window (sidebar sections, built from capabilities)
  Listening   modes, noise control, immersive audio, wind block
  Sound       EQ, user presets
  Sources     active, connected, remembered, other Macs
  Device      battery, identity, firmware, connection, multipoint, rename

Settings window   General, Shortcuts, Handoff, Advanced
Onboarding        first launch only
Protocol Console  separate window, hidden behind Advanced setting
About             independent, unofficial project statement
```

A sidebar section appears only if the device declares at least one capability for it. Sections never appear empty. Device is always present.

**App presence:** menu-bar-first. The Dock icon appears only while a window is open, with a setting to keep it always.

## User flows

### A. First launch and pairing
1. Welcome: what QuietDeck does, plus the independent project statement.
2. Bluetooth permission: explain why, then trigger the system prompt.
3. Find headphones: list paired, supported devices. If none are found, explain pairing in System Settings and offer a button that opens it. QuietDeck does not pair devices itself in the MVP.
4. Connect: read device state, show progress per step.
5. Finish: optional Launch at login, and a pointer to the menu bar icon.

Permission denied leads to a screen with an Open System Settings button, and rechecks when the app regains focus.

### B. Daily mode switching
Click the menu bar icon, click a mode. Two clicks, or one global shortcut. A shortcut shows a small transient HUD (mode name and icon), which can be turned off. The panel stays open after a change, so several adjustments are possible.

### C. Switching between two Macs (main use case)
**First-time link:** Settings > Handoff lists QuietDeck on the local network. Choosing one shows a 6-digit code on both Macs, and you confirm the match. Unlinked Macs cannot trigger anything.

**Daily use:** on Mac A, click Send audio next to Studio Mac, or press the hotkey.
1. The row shows "Sending…" and the control stays cancellable.
2. Mac B takes over using the best available route (below).
3. Both Macs update. Mac B shows a short HUD, "Audio is here now".
4. Failure leaves audio where it was, with a reason and a Try again action.

Routes, tried in order. The UI is the same for both, so it does not depend on the outcome of protocol discovery:
- **Headset route:** a BMAP source-switch command, if discovered and available without authentication.
- **Bluetooth route:** Mac A releases and Mac B connects, using standard macOS Bluetooth calls.

Pull is also supported: on Mac B, "Bring audio here".

### D. Error and disconnected states
| State | Panel and window behavior | Action |
|---|---|---|
| Not connected | Header says so, controls dimmed but laid out in place | Connect |
| Connecting | Spinner in header, last known values dimmed | Cancel |
| Audio on another source | Header names it; controls stay active if the session is alive | Bring audio here |
| Session busy (another app holds the channel) | Inline banner explaining it | Try again |
| Command failed | Value rolls back, inline message beside the control | Try again |
| Command rejected or needs authentication | Control shows "Not available on this firmware", no retries | Learn more |
| Bluetooth off | One full-panel message | Open Bluetooth settings |
| Link to other Mac lost | Mac row shows Offline; never blocks local control | None |

Connection state comes from whether the session answers, not from `isConnected`.

### E. Device with limited capabilities
Using QC45-like data: no noise slider, no immersive audio. Modes remain, the Listening section shrinks to the mode row, and the window height follows the content with no gaps or disabled placeholders. Rule: **hide what a device can never do; disable only what is temporarily unavailable.**

## Screen specs

### Menu bar icon
Template image, `headphones`. Optional setting: show the current mode glyph instead. Small dot overlay when disconnected. Tooltip and VoiceOver announce device, mode and battery.

### Menu bar panel
Fixed width 320 pt, height follows content, no scrolling at normal content sizes.
- **Header:** device name, connection line, battery percentage and icon.
- **Modes:** 2×2 grid of wide tiles (icon beside label), so labels never touch tile edges, including in German. Arrow keys move, Space selects. A Custom state deselects all and the header shows "Custom".
- **Noise control:** slider, 0–10.
- **Audio source:** active source with a check, then other sources and linked Macs. Up to 4 rows, then "All sources…" opens the main window. This is the only accent-filled control in the panel.
- **Footer:** Open QuietDeck, settings gear.

EQ, immersive audio and wind block are window-only by default, to keep the panel calm.

### Main window
Default 760×560, minimum 420×480.
- **Listening:** hero card with the current mode, a one-line description and a battery ring; then mode tiles; a grouped list with noise control, immersive audio (segmented Off/Still/Motion) and wind block (toggle); and a source strip ("Playing on This Mac", Send to Studio Mac), so handoff is one click from the default screen.
- **Sound:** three vertical sliders (bass, mid, treble), band count and range from the capability, with value readouts. Preset picker with Save, Rename, Delete and Reset to flat. Presets are stored locally. Unsaved edits show "Edited".
- **Sources:** three groups: Active, Connected, Remembered, plus Other Macs. Each row has device type icon, name, state and one action. Multipoint toggle appears only if verified as usable without authentication.
- **Device:** large battery readout, model, firmware, serial if available, connection details, rename if supported, Forget in QuietDeck.

The toolbar shows the device picker (when more than one is known) and battery.

### Settings (standard tabbed window)
- **General:** Launch at login, Dock icon behavior, menu bar icon style, HUD on/off.
- **Shortcuts:** one recorder per mode, plus Send audio to other Mac, Cycle mode, Show panel. No defaults, to avoid conflicts.
- **Handoff:** enable, this Mac's name, linked Macs, link and unlink.
- **Advanced:** Show Protocol Console, log level, export diagnostics.

### Protocol Console
Separate window, enabled in Settings > Advanced or by holding Option on the app menu.
- **Log table:** time, direction, driver, address (`[31.3]`), operator, hex, decoded note. Monospaced. Filter by driver, direction, operator, text. Pause and clear.
- **Composer:** driver picker; for Bose, fields for fblock, function, operator, payload hex, with live frame preview. The operator list offers GET, START and SETGET only. Pure SET is not offered. Each driver supplies its own composer rules.
- **History:** sent frames, resend, annotate.
- **Export:** text and JSON with timestamps, so logs line up with PacketLogger captures. Device address redacted by default.
- A persistent notice warns that raw frames can change device state.

### Onboarding
Single window, 520×440, one idea per step, as in Flow A. Skippable after the permission step.

### About
Standard panel with version, links, and this statement: "QuietDeck is an independent, unofficial project. It is not affiliated with or endorsed by any headphone manufacturer. Product names are used only to describe compatibility."

## Visual direction

**App icon concept:** an abstract deck: two or three stacked rounded glass layers, the top one carrying a single soft sound arc that fades to stillness. Deep slate to blue-indigo. No headphone silhouette resembling any product and no manufacturer marks. Delivered as an Icon Composer layered icon for macOS 26+ with a flattened fallback.

**Layout:** 8 pt grid. Panel margins 12, window content margins 20, group spacing 16, row height 32 minimum, tile radius 10, group radius 10 (system values on macOS 26).

**Typography:** SF Pro through system text styles only, so Dynamic Type-style scaling and localization work.
| Role | Style |
|---|---|
| Section title | `.title2` semibold |
| Group header | `.headline` |
| Row label | `.body` |
| Secondary | `.callout` secondary |
| Readouts | `.title3`, monospaced digits |
| Console | `.body` monospaced |

**Color tokens** (semantic, asset catalog with light, dark and high-contrast variants):
| Token | Maps to |
|---|---|
| `accent` | system accent, follows user choice |
| `surface.panel` | system material (`.popover`), Liquid Glass on 26+ |
| `surface.group` | `controlBackgroundColor` |
| `text.primary`, `text.secondary` | `labelColor`, `secondaryLabelColor` |
| `status.ok` | `systemGreen` |
| `status.warning` | `systemOrange` (battery under 20%) |
| `status.error` | `systemRed` (battery under 10%, failures) |

No custom brand color inside the app. Color never carries meaning alone: every status has an icon and text.

**SF Symbols:** Quiet `moon.fill`, Aware `ear`, Immersion `sparkles`, Cinema `film`, Custom `slider.horizontal.3`, Sound `slider.vertical.3`, Sources `arrow.left.arrow.right`, Device `headphones`, wind `wind`, immersive `waveform`, Macs `laptopcomputer` and `desktopcomputer`, phones `iphone`, battery `battery.100percent` family, console `terminal`. Availability on macOS 14 is checked during implementation.

**Design system:** Apple macOS (Human Interface Guidelines). Sections use the grouped form style of System Settings.

**Sidebar:** native macOS source list, full window height and translucent, with the traffic lights at the top. A header shows device name, connection and battery. Rows are 28 pt with system selection (accent fill, white text and symbol). The window title sits at the top of the content pane.

**Liquid Glass:** a defining part of the look on macOS 26+. The menu bar panel is the strongest glass surface; the app uses glass on the sidebar, toolbar and window chrome, with content groups kept legible and glass never stacked on glass. On 14–25, standard materials with the same layout. No layout differs between the two.

**Motion:** 150–250 ms system springs. Mode selection slides the highlight between tiles; sending audio moves a subtle pulse along the row. With Reduce Motion: crossfades only, no pulse.

**Responsive behavior:**
| Width | Behavior |
|---|---|
| Over 700 pt | Sidebar visible, mode tiles in one row, Sound shows sliders and presets side by side |
| 520–700 pt | Sidebar collapsible, Sound stacks presets below sliders |
| Under 520 pt | Sidebar collapses to a toolbar picker, mode tiles become 2×2 |

The panel is always fixed width.

## Accessibility and localization

- **VoiceOver:** every control has label, value and hint, for example "Noise control, 8 of 10". Mode tiles are a radio group. State changes and handoff results are announced.
- **Keyboard:** full tab order, arrow keys in tiles and sliders, Command-1 to 4 for sidebar sections, Escape closes the panel.
- **Increase Contrast:** adds borders to tiles and groups, solid fills replace materials.
- **Reduce Transparency:** materials become opaque.
- **Localization:** the app ships fully in English and German, following the system language, using String Catalogs. Layouts are tested with German, which runs around 30% longer.
- **German terms (draft):** Hörmodus, Klang, Quellen, Gerät; modes Ruhe, Umgebung, Immersion, Kino; Geräuschregelung, Immersives Audio (Aus, Fest, Bewegung), Windschutz, Audio senden.

## Open items

**Signing:** a Developer ID certificate is needed before notarized builds. Development builds use ad-hoc signing until then.
