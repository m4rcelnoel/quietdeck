# Bose BMAP: verified behavior

This records what has been confirmed on real hardware. The full command list, including unverified entries, is in [the implementation plan](../plan/phase-2-implementation-plan.md).

## Test device

| Property | Value |
|---|---|
| Model | QC Ultra Headphones (2nd Gen), reported name `Bose QC Ultra 2 HP` |
| Bluetooth vendor and product ID | `0x009E`, `0x4082` |
| Firmware | `10.12.14+gde0210e` from `[0.5]`; macOS shows 10.12.14 |

Reference notes describe firmware 8.2.20, so differences are possible.

## Verified

| Item | Result |
|---|---|
| RFCOMM channel 2 with async open | Opens in 60 to 180 ms |
| `[2.2]` GET battery | Byte 0 is the percentage |
| 100 sequential transactions | No failures; median 24 to 28 ms, maximum 76 ms |
| App Sandbox | Works with the Bluetooth entitlement |
| `isConnected` | Reported false while the headset was connected, so it must not be trusted |
| Power cycle | Session reports the loss within seconds and reopens about 120 ms after macOS reports the device connected |

## Reads

All without authentication.

| Address | Meaning | Observed |
|---|---|---|
| `[0.5]` GET | Firmware | ASCII |
| `[1.2]` GET | Device name | `00` then UTF-8 |
| `[1.5]` GET | Noise control info | `0b 00 03` |
| `[1.7]` GET | Equalizer | 3 records `[min, max, current, band]` |
| `[1.10]` GET | Multipoint | Bit 0 is the setting: `07` on, `06` off |
| `[1.11]` GET | Sidetone | `01 02 0f` |
| `[1.24]`, `[1.27]` GET | Auto play/pause, auto answer | `01` |
| `[2.2]` GET | Battery | `[percent, ff, ff, 00]` |
| `[4.4]` GET | Paired devices | One leading byte, then 6-byte addresses. The leading byte was 3 with 4 addresses listed, so it isn't a simple count |
| `[4.5]` GET `[mac]` | Device details | See below |
| `[5.1]` GET | Active source | `[supported(2), type, mac(6)]`; address matched this Mac while it was the source |
| `[31.2]` GET | Mode summary | `04 07 00 00 00 7f 02`; last byte matched the current mode |
| `[31.3]` GET | Current mode | Index, `ff` for custom |
| `[31.8]` GET | Favorites | `0b 00 17` |
| `[31.10]` GET | Audio settings | `[cnc, auto_cnc, spatial, wind, anc]` |
| `[31.11]` GET | Preset mask | `1f ff ff ff ff` |

Not available on this firmware:

| Address | Result |
|---|---|
| `[2.3]` GET charging | Error 4, function not supported |
| `[4.12]` GET routing | Error 4 while idle. Reference notes say this means the routing table is empty |

### `[4.5]` device details

Layout: `[mac(6), status, type?, unknown, name...]`, with the name starting at offset 9.

Reference code searches for a `03` marker to find the name. That fails here, because `03` can also appear as the status byte.

| Device | Status | Second byte | Third byte |
|---|---|---|---|
| This Mac, active source | `03` | `01` | `01` |
| Computer, apparently connected | `01` | `01` | `03` |
| Phone, not connected | `00` | `02` | `03` |
| Computer, not connected | `00` | `01` | `03` |

Status bit 0 means connected: turning multipoint off dropped the second computer, and its status went from `01` to `00`. It didn't reconnect by itself after multipoint was turned on again.

The second byte appears to be the device type (1 computer, 2 phone).

Status bit 1 does not mean "playing". It stayed on this Mac after `[5.1]` reported another device as the active source, so it may mark the device holding the control session. `[5.1]` is the only reliable source for the active device. The order of `[4.4]` can change after a switch.

## Writes

All without authentication. Each was checked by reading back, and the original state was restored afterwards.

| Command | Response | Effect |
|---|---|---|
| `[31.3]` START `[index, 0]` | RESULT with the index | Mode changes; the device applies the mode's settings itself |
| `[31.10]` SETGET | STATUS echoing the new values | Applies at once; `[31.3]` then reads `ff` (custom) |
| `[1.7]` SETGET `[value, band]` | STATUS with all three bands | Applies at once, negative values included |

| `[1.10]` SETGET `[0 or 1]` | STATUS with the new value | Works without authentication. The control session stayed open |

`[4.12]` START `[0x82, mac]` answered error 4 on every attempt while no stream from the target was starting, for both this Mac and another connected device. The source didn't change. This matches the reference notes, which say the routing table is only filled while the target's stream starts.

Settings applied by each mode, read from `[31.10]`:

| Mode | Index | cnc | Spatial | ANC |
|---|---|---|---|---|
| Quiet | 0 | 0 | off | on |
| Aware | 1 | 10 | off | on |
| Immersion | 2 | 0 | motion (2) | on |
| Cinema | 3 | 0 | still (1) | on |

Consequences for the driver:

- After a mode change it reads `[31.10]`, so no preset values are stored in the app.
- `[31.10]` and `[1.7]` report the real new state in their response, so no extra read is needed.
- The Wind Block and ANC bytes read back correctly, but their audible effect hasn't been confirmed by ear.

## Switching sources

Observed with this Mac and a phone connected:

- When the phone started playing while this Mac was the active source, `[5.1]` changed to the phone by itself. No `[4.12]` command had succeeded.
- `[4.12]` answered error 4 throughout, including during that change.
- `[4.12]` to this Mac also answered error 4 while the phone was active, with and without a silent audio stream running on this Mac. The silent stream alone didn't move the source either. The phone was playing at that moment: a source that's playing keeps the headset.
- With a phone playing, `[5.3]` START `[02]` paused it. A silent audio stream started on this Mac then became the active source within about 100 ms, so the whole change took about 2 seconds. QuietDeck uses this instead of `[4.12]`.

## Connecting a remembered device

`[4.1]` START `[00, mac(6)]` answers PROCESSING and asks the headset to connect that device. Without the leading `00`, it answers error 6. No software is needed on the other device.

The first byte of `[4.4]` shows progress: `05` while connecting, then `03` with two devices connected, or `01` with one. In `[4.5]` the target shows status `01` during the attempt, before it's known to work, so that status alone doesn't prove a connection.

The headset holds two connections. Connecting a third drops one: with this Mac and a phone connected, the phone was dropped, and it didn't return by itself. A second request during a running attempt answered error 13.

An attempt to a computer that wasn't available fell back to status `00`. Two computers can be connected at the same time, including a Mac and a Windows PC. Connecting a Windows PC took 4.6 seconds, and bringing audio back from it to this Mac took 1.9 seconds.

## Changes made on the headset

Cycling through modes with the multifunction button sent no frames to an open BMAP session, across 40 seconds of observation. A later read returned the new mode and settings correctly.

The headset may need to be asked to send notifications, which hasn't been investigated. Until then, the app has to read the state again to notice such changes.

Press and hold cycles only through modes marked as favorites. A mode outside the four built-in presets currently reads as custom.

## Not yet verified

- `[4.12]` START succeeding under any condition
- `[1.2]` SETGET rename
- Changes made in the official app while a session is open
- Two Macs holding a BMAP session at the same time
