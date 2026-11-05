# QuietDeck: implementation plan (Phase 2)

Status: approved. Section 4 is the original draft; `docs/protocol/bose-bmap.md` records what hardware confirmed, and wins where they differ.
Design input: [phase-1-ui-ux.md](../design/phase-1-ui-ux.md).

## 1. What changed since Phase 1

Phase 1 assumed that state reads, source listing and source switching were unknown. Further research found that two more open projects document them for the QC Ultra 2:

- **bosectl** (`aaronsb/bosectl`, MIT): protocol notes and multi-language libraries.
- **Quiet Rebellion** (`MadEyez/quietrebellion`, MIT): Android app for this exact headset, with source switching and a multipoint toggle.

Consequences:

| Topic | Before | Now |
|---|---|---|
| Reconciliation on connect | Unknown | GET commands documented for mode, audio settings and EQ |
| Active source, paired devices | Unknown | `[5.1]`, `[4.4]`, `[4.5]` documented |
| Source switching | Unknown | `[4.12]` START documented, with a serious timing limit (section 6) |
| Multipoint toggle | Unknown | `[1.10]` SETGET documented, sources partly conflict |
| Wind Block | Never exercised | Field documented, with an audible side effect |
| Firmware version, device name | Unknown | `[0.5]`, `[1.2]` documented |

The Protocol Console remains essential, but its job moves from discovery to verification. Nothing in this plan counts as verified until tested on your hardware.

## 2. Architecture

### Modules

```
App (Xcode target: SwiftUI, AppModel, menu bar, settings, console UI)
 |
 +-- QuietDeckCore     vendor-neutral: capabilities, driver protocol,
 |                     registry, device state, command scheduler
 +-- BoseDriver        BMAP codec, QC Ultra 2 definition, raw frame policy
 |     depends on: QuietDeckCore, TransportInterface
 +-- BluetoothTransport
 |     TransportInterface   byte transport protocol, no Bluetooth imports
 |     RFCOMMBridge         Objective-C target wrapping IOBluetooth
 |     BluetoothTransport   session lifecycle, reconnection, timeouts
 +-- HandoffKit        Bonjour, Mac-to-Mac protocol, link trust, output routing
 |     depends on: QuietDeckCore
 +-- QuietDeckTesting  MockDriver, MockTransport, fixtures (tests and previews)
```

Rules, enforced by package dependencies:
- `QuietDeckCore` imports no Bluetooth framework and no vendor module.
- `BoseDriver`'s codec is a separate target with no dependencies at all.
- The App imports vendor modules in exactly one file, the driver registration. No view can see a vendor type.

### Repository layout

```
QuietDeck.xcodeproj
App/                    app target, assets, String Catalogs, entitlements
Packages/QuietDeckCore/
Packages/BluetoothTransport/
Packages/BoseDriver/
Packages/HandoffKit/
Packages/QuietDeckTesting/
docs/  design/  plan/  protocol/  adr/  adding-a-driver.md
scripts/                build, sign, notarize
```

### Data flow

```
View --intent--> AppModel --> CommandScheduler --> HeadphoneDriver
                    ^          (debounce,            |
                    |           coalesce)            v
                    |                            transport --> RFCOMM
                    +-------- DeviceEvent <---- frame router
```

Each control tracks two values: **desired** (what the user just set) and **confirmed** (what the device last reported). The UI shows desired while a command is pending. On failure it falls back to confirmed and shows the inline error from the Phase 1 design. On connect, and after a mode change, the driver reads the hardware and replaces confirmed.

**After writing, read back.** Sources report that some SETGET commands echo a value without applying it. For anything not covered by a reliable response, the driver follows a write with a GET.

### Concurrency model (Swift 6, strict)

| Component | Isolation | Notes |
|---|---|---|
| `AppModel` and all views | `@MainActor`, `@Observable` | One instance shared by panel and main window |
| IOBluetooth bridge | Main run loop | Delegate callbacks are delivered there; forwarded immediately as `Data` into an `AsyncStream` |
| `RFCOMMSession` | `actor` | Owns the state machine, cooldown and reconnection |
| Transaction queue | Single consumer task | An actor alone is not enough: it can interleave across `await`, so one task drains a FIFO and runs one transaction at a time |
| Frame router | Inside the driver | Matches responses to the pending transaction; anything else becomes a `DeviceEvent` |
| `CommandScheduler` | `actor` | 500 ms sliders, 150 ms discrete controls, latest value wins |
| `HandoffService` | `actor` | Network.framework callbacks bridged into async |

All values crossing an isolation boundary are `Sendable`. `@unchecked Sendable` is allowed only in the small wrapper around the bridge, with the reason documented.

### Session state machine

```
idle -> opening (async open, 8 s) -> open -> closing -> cooldown (650 ms) -> idle
                      |                |
                      +-- failed       +-- lost -> retry ~2 s, then ~10 s -> idle
```

Connected means "the session answers", never `isConnected`. There is no automatic reconnect after an intentional disconnect. A disconnect during a multipoint change is expected and reconnects quietly.

## 3. Driver interface and capability model (draft)

```swift
/// Static description of what a device can do. The UI is built from this.
public struct DeviceCapabilities: Sendable, Equatable {
    public var listeningModes: ListeningModesCapability?
    public var noiseControl: LevelCapability?          // e.g. 0...10
    public var spatialAudio: OptionsCapability<SpatialAudioMode>?
    public var windBlock: ToggleCapability?
    public var equalizer: EqualizerCapability?         // bands and range
    public var battery: BatteryCapability?
    public var audioSources: AudioSourcesCapability?
    public var multipoint: ToggleCapability?
    public var rename: RenameCapability?
}

/// Live values. A nil value means "not read yet", not "unsupported".
public struct DeviceState: Sendable, Equatable {
    public var mode: ListeningModeSelection?           // .preset(id) or .custom
    public var noiseLevel: Int?
    public var spatialAudio: SpatialAudioMode?
    public var windBlock: Bool?
    public var equalizer: [EqualizerBandValue]?
    public var battery: BatteryStatus?
    public var sources: AudioSourceList?
    public var multipoint: Bool?
}

public enum DeviceCommand: Sendable {
    case setMode(ListeningMode.ID)
    case setAudio(noiseLevel: Int?, spatial: SpatialAudioMode?, windBlock: Bool?)
    case setEqualizerBand(id: EqualizerBand.ID, value: Int)
    case setMultipoint(Bool)
    case switchSource(AudioSource.ID)
    case rename(String)
}

public protocol HeadphoneDriver: Sendable {
    static var descriptor: DriverDescriptor { get }    // id, display name
    static func match(_ device: DiscoveredDevice) -> DriverMatch?
    init(device: DiscoveredDevice, transport: any ByteTransport)

    var capabilities: DeviceCapabilities { get async }
    var events: AsyncStream<DeviceEvent> { get }

    func connect() async throws
    func disconnect() async
    func refreshState() async throws -> DeviceState
    func perform(_ command: DeviceCommand) async throws

    var rawConsole: (any RawFrameConsole)? { get }     // nil if unsupported
}

public protocol RawFrameConsole: Sendable {
    var composer: FrameComposerSpec { get }            // fields, allowed operators
    var traffic: AsyncStream<FrameLogEntry> { get }
    func evaluate(_ frame: RawFrame) -> RawFrameVerdict  // allow, confirm, deny
    func send(_ frame: RawFrame) async throws
}
```

`DriverRegistry` scores `match` for each driver using name, UUID, vendor or product ID and SDP records, and picks the most specific. `ByteTransport` is the only transport a driver sees, so `MockTransport` can replay recorded sessions. Capabilities are `async` so a driver can refine them after reading the device, for example by removing Wind Block if firmware rejects it.

## 4. Bose protocol map

Frame: `fblock, function, flags, length, payload`. Flags: `(device_id << 6) | (port << 4) | operator`. The codec keeps the upper bits and masks only for the operator.

**Status legend.** `R` from reference, tested on hardware by the cited project. `R?` from reference but sources conflict or detail is missing. `U` unknown. `V` verified by us: **no entry has this status yet**. Each row moves to `V` during M3, recording firmware version and capture.

**Sources.** N: N1et/bose-qc-gui. B: bosectl. Q: Quiet Rebellion.

### MVP

| Feature | Address | Op | Payload | Status | Src |
|---|---|---|---|---|---|
| Read battery | `[2.2]` | GET | response byte 0 = percent | R | N B Q |
| Read charging | `[2.3]` | GET | 0 or 1 | R | Q |
| Read mode | `[31.3]` | GET | byte 0 = index; `0xFF` = left saved mode (Custom) | R | B Q |
| Set mode | `[31.3]` | START | `[index, voice_prompt=0]`: 0 Quiet, 1 Aware, 2 Immersion, 3 Cinema | R | N B Q |
| List modes and names | `[31.1]` then `[31.6]` | START, STATUS | 38 to 48 byte records, sizes differ between sources | R? | B Q |
| Read audio settings | `[31.10]` | GET | `[cnc, auto_cnc, spatial, wind, anc]` | R | Q |
| Write audio settings | `[31.10]` | SETGET | same; `auto_cnc` must stay 0 (error 8) | R | N B Q |
| Wind Block | `[31.10]` byte 3 | SETGET | 0 or 1 | R | B Q |
| Read EQ | `[1.7]` | GET | 3 records `[min, max, current, band]` | R | B Q |
| Write EQ band | `[1.7]` | SETGET | `[value, band]`, signed, -10 to +10 | R | N B Q |
| Firmware version | `[0.5]` | GET | ASCII | R | Q |
| Device name | `[1.2]` | GET | `[flag, utf8...]` | R | B Q |

Notes:
- `cnc` is inverted: UI level = `10 - cnc`.
- **Wind Block masks noise control.** With wind on, the noise level has no audible effect. The UI shows a short hint in that state.
- Mode presets are firmware values. The driver reads `[31.10]` after a mode change instead of hard-coding presets as N does. This should also remove the need for N's fixed 750 ms batch.

### High priority: sources and multipoint

| Feature | Address | Op | Payload | Status | Src |
|---|---|---|---|---|---|
| Active source | `[5.1]` | GET | `[supported(2), type, mac(6)]`; type 1 = Bluetooth, 2 = aux | R | B Q |
| Paired device list | `[4.4]` | GET | `[count?, mac(6)...]`, zeroed entries skipped | R | B Q |
| Paired device name | `[4.5]` | GET `[mac]` | `[mac(6), ?, ?, 0x03, name...]`; meaning of unknown bytes may include connection state | R? | Q |
| Routing available | `[4.12]` | GET | error 4 = routing table empty | R? | Q |
| Switch source | `[4.12]` | START | `[0x82, mac(6)]`; RESULT, STATUS or ERROR | R? | B Q |
| Connect a remembered device | `[4.1]` | START | MAC expected, format unknown | U | B |
| Read multipoint | `[1.10]` | GET | observed `0x07`; Q reads bit `0x02` | R? | B Q |
| Write multipoint | `[1.10]` | SETGET | B and Q use `[0 or 1]`; B also lists it as auth-blocked for SET/START; device disconnects while applying | R? | B Q |
| Rename | `[1.2]` | SETGET | UTF-8, untested in part of B | R? | B Q |
| Unsolicited STATUS when buttons are pressed | various | STATUS | Unknown whether and when sent | U | none |
| Two Macs holding BMAP sessions at once | n/a | n/a | Unknown | U | none |

### Out of scope, and guarded

| Address | Reason | Console policy |
|---|---|---|
| Block 18, all functions | Manufacturer authentication and keys | **Deny, including GET** |
| Block 3 | Firmware update | Deny |
| Block 8 | Debug | Deny |
| Pure SET (operator 0) | Authentication-gated | Deny (not offered) |
| `[4.3]` remove device, `[4.7]` clear list, `[31.9]` reset | Destructive | Deny by default |
| `[7.4]` power, `[4.8]` pairing mode, `[4.2]` disconnect | Disruptive but harmless | Confirm each time |
| `[1.9]` button remapping | Sources disagree on whether it needs authentication | Not used |

### Verifying and discovering

1. Run a scripted GET sweep from the console, read-only, and save results as fixtures.
2. For each write: read, write, read back, then confirm by ear or in the official app.
3. Compare with PacketLogger captures for timing and framing.
4. Record outcomes in `docs/protocol/bose-bmap.md`. After a firmware update, repeat steps 1 and 2.

## 5. Adding a vendor driver (summary)

This becomes `docs/adding-a-driver.md`.

1. Create `Packages/<Vendor>Driver`, depending on `QuietDeckCore` and `TransportInterface`.
2. Put the codec in its own target with no dependencies, and test it first.
3. Implement `HeadphoneDriver`: `match`, capabilities, `refreshState`, `perform`.
4. If the transport isn't RFCOMM, add a new `ByteTransport`. Drivers don't change.
5. Provide a `RawFrameConsole` with a deny-by-default policy for authentication, firmware and destructive functions.
6. Add recorded fixtures and contract tests. `DriverContractTests` in `QuietDeckTesting` runs the shared suite against any driver.
7. Add one line to the App's driver registration.

No UI or Core change should be needed. If one seems necessary, the capability model is extended first, as its own reviewed change.

## 6. Multi-Mac handoff

### How the headset behaves (verified)

A source that is playing keeps the headset. Once the line is free, a new stream takes over within about 100 ms. The routing command `[4.12]` never succeeded in any test, so QuietDeck doesn't use it.

Verified from a phone to this Mac: pausing the source through the headset with `[5.3]` and then starting a silent stream moved audio in about 2 seconds, with no action on the phone. See `docs/protocol/bose-bmap.md`.

### Sequence (verified from phone to Mac, not yet from Mac to Mac)

```
Mac A (audio now)                     Mac B (target)
"Send audio" --- prepare handoff ---> set default output to headset
             <--- ready -------------
START [5.3] [02] (pause)
             ---- paused ----------->  start a silent stream
                                       wait until [5.1] names Mac B
                                       stop the stream, show "Audio is here now"
```

Either Mac can send the pause if it holds a BMAP session. Whether two Macs can hold sessions at once is still unknown, so the design needs only one.

**Fallback (Bluetooth route):** if this fails, Mac A disconnects its link and Mac B connects with `IOBluetoothDevice.openConnection()`, then sets the default output.

The user interface is identical for both routes.

### What the Macs must exchange

Bluetooth address (`IOBluetoothHostController`), display name and device ID. This maps headset MACs to linked Macs, so Sources shows "Studio Mac" rather than an address.

`HandoffKit` also owns output routing through CoreAudio. Routing the headset to Mac B is not enough if Mac B is still playing through its speakers.

### Network and trust

- **Discovery:** Bonjour `_quietdeck._tcp` via Network.framework.
- **Linking:** each Mac generates a Curve25519 identity key stored in the Keychain. On first link, the Macs exchange keys using a commit-then-reveal step, and both display a 6-digit code derived from the transcript. You confirm the match. This resists an attacker on the network, unlike a code used directly as a password, which could be brute-forced offline.
- **Sessions:** TLS 1.3 with a pre-shared key derived from the linked identities. Unlinked Macs are refused.
- **Messages:** versioned, Codable, length-prefixed: `hello`, `status`, `prepareHandoff`, `streamReady`, `handoffDone`, `handoffFailed`, `unlink`. Unknown messages are ignored for forward compatibility.
- **Timeouts:** the whole handoff is limited to 8 s. Failure leaves audio where it was.

## 7. Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Pause and stream fail between two Macs | Low | High | Verified from a phone to a Mac; test first in M7; use Bluetooth route fallback |
| Bluetooth route is slow or macOS refuses it | Medium | High | Measure in M3; if both routes fail, reassess the feature with you before M7 |
| Second Mac can't hold a session while the first does | Medium | Medium | Design needs only one session; second Mac shows last status via Bonjour |
| Firmware update changes or gates commands | Medium | Medium | Capabilities degrade per feature; error 5 shows "Not available on this firmware" and stops retries; fixtures record firmware version |
| Sources are wrong or conflict | Medium | Low | M3 verifies every command; read-back after writes |
| Official app or another tool holds the channel | High | Low | Detect failure and show the "Session busy" state; retry on your action only |
| IOBluetooth is stale, deprecated or changes | Medium | High | All access stays inside one small bridge; async open only; `isConnected` never trusted |
| Stack stays busy after close | Medium | Medium | One persistent session, 650 ms cooldown |
| Sleep, wake and fast user switching | High | Medium | Observe sleep and wake; close before sleep, reconnect after wake |
| Silent stream briefly interrupts other audio | Medium | Low | Runs only during handoff; tested in M7 |
| App Sandbox blocks a required API | Low | Medium | Spike in M2; see open decisions |

## 8. Milestones

Each milestone is a small series of focused commits. After each one you get a summary and a hardware test list. Protocol-dependent milestones are marked **HW** and need your headset.

| # | Milestone | Contents | Acceptance criteria |
|---|---|---|---|
| M0 | Foundation | Repo, packages, app shell, README with independence statement, CI script, lint | `xcodebuild` and `swift test` pass; empty menu bar app launches |
| M1 | Core and codec | Capability model, registry, BMAP codec, MockDriver, MockTransport | Tests: round trip, fragmented input, several frames per read, error frames, oversized payload, registry matching |
| M2 | Transport **HW** | ObjC bridge, session actor, transaction queue, reconnection | Opens channel 2, reads battery, survives 100 sequential transactions, reconnects after power cycle |
| M3 | Console and verification **HW** | Protocol Console, frame policy, GET sweep, handoff spike | Protocol map updated with verified status; go or no-go on handoff routes |
| M4 | Bose driver **HW** | All MVP commands, state reconciliation, scheduler | Hardware state matches UI model after connect, after hardware button press, and after commands from the official app |
| M5 | Core UI | Menu bar panel, main window: Listening, Sound, Device | Matches approved mockup; capability-limited mock looks complete; all error states shown with MockDriver |
| M6 | Sources **HW** | Sources screen, switching with phone or second Mac, multipoint toggle if verified | Source list correct; switch works or fails with clear reason; toggle hidden if not verified |
| M7 | Handoff **HW** | HandoffKit, linking, one-click and hotkey handoff | Link two Macs; 20 consecutive handoffs; record success rate and median time, target over 90% and under 5 s |
| M8 | Finish | Onboarding, settings, global shortcuts, launch at login, German, accessibility pass | VoiceOver and keyboard-only walkthrough; Reduce Motion, Increase Contrast and Reduce Transparency checked; German complete |
| M9 | Release | Signing, notarization, updates, DMG, docs | Notarized build installs and updates on a clean Mac |

M3 comes before the UI on purpose: its results decide how M6 and M7 are built.

## 9. Testing strategy

| Layer | Approach |
|---|---|
| Codec | Swift Testing unit tests, plus property-style round trips with generated frames |
| Core and registry | Unit tests on capabilities, matching and state reconciliation |
| Driver | `MockTransport` replaying fixtures recorded from real sessions; contract tests |
| Scheduler | Injected clock, so debounce tests are exact and fast |
| Session | Fake bridge simulating timeouts, partial reads and sudden loss |
| App model | MockDriver: optimistic update, rollback, Custom state |
| Handoff | In-memory transport; protocol tests with two simulated peers; failure injection |
| UI | Previews for every state and both languages; snapshot tests for key screens at three window sizes |
| Hardware | Checklist in `docs/testing/hardware-checklist.md`, repeated per milestone and after firmware updates |

## 10. Release strategy

- **Signing:** Developer ID Application certificate, Hardened Runtime, secure timestamp.
- **Entitlements and Info.plist:** `com.apple.security.device.bluetooth`, `NSBluetoothAlwaysUsageDescription`, `NSLocalNetworkUsageDescription`, `NSBonjourServices`.
- **Notarization:** `notarytool` with credentials in the Keychain profile, then stapling. Scripted in `scripts/`.
- **Distribution:** signed, notarized DMG.
- **Updates:** Sparkle with EdDSA-signed appcast, user confirmation required.
- **Versioning:** SemVer, changelog generated from Conventional Commits.
- **Launch at login:** `SMAppService.mainApp`.
- **Global shortcuts:** Carbon hot keys behind a small wrapper. No Accessibility permission needed.

## 11. Open decisions

1. **App Sandbox.** Plan: enable it with Bluetooth and network entitlements if the M2 spike works, otherwise ship non-sandboxed with Hardened Runtime.
2. **Third-party dependencies.** Plan: Sparkle only.
3. **Project license.** Decided: Apache License 2.0.
4. **Second headset or test Macs.** M7 needs two Macs. Testing with a third source, such as a phone, is useful but optional.
