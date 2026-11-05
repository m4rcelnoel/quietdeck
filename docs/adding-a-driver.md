# Adding a headphone driver

A new brand is a new driver module. The UI and app logic must not need changes.

1. Create `Packages/<Vendor>Driver`, depending on `QuietDeckCore` and `TransportInterface`.
2. Put the wire format in its own target without dependencies, and test it first. `BMAPCodec` is the example.
3. Implement `HeadphoneDriver`:
   - `match` recognizes the device by name, service UUID, or vendor and product ID.
   - `capabilities` declares what the device can do. Leave out anything not verified on hardware.
   - `refreshState` reads the device. A value that can't be read stays `nil`.
   - `perform` runs a command. Throw `DriverError.authenticationRequired` if the device demands it, and remove that capability.
4. Report only changes nobody requested through `events`. `connect()` reports its own result by returning or throwing.
5. Provide a `RawFrameConsole` whose policy denies authentication, firmware and destructive functions by default. Never access manufacturer authentication or keys.
6. If the device doesn't use RFCOMM, add a `ByteTransport`. Drivers don't change for this.
7. Register the driver in `App/QuietDeck/DriverCatalog.swift`, and set up its transport there. No other app file may import a vendor module.
8. Add tests built from recorded device responses, and record what you verified in `docs/protocol/`.

If a device needs something the capability model can't express, extend the model first as its own reviewed change.
