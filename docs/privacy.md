# Privacy

This describes what the app does with data. It's a technical description, not legal advice.

## What the app does not do

- No account or sign-in.
- No analytics, tracking, advertising or crash reporting.
- No connection to any server operated by the developer or a headphone manufacturer.

## What stays on this Mac

| Data | Purpose | Where | How long |
|---|---|---|---|
| Settings, equalizer presets, shortcuts | Remembering your choices | App container (`UserDefaults`) | Until deleted |
| Bluetooth addresses and names of devices paired with the headphones | Showing and connecting sources | Memory only | While the app runs |
| Headphone state, such as battery and mode | Showing controls | Memory only | While the app runs |

Notifications are created on this Mac and don't pass through any server.

Release builds write no log files. Debug builds can write diagnostic logs to the app container.

Protocol Console exports are created only on request. Addresses and names are removed by default.

## Deleting data

Settings > About QuietDeck > Delete removes everything the app has stored on this Mac, then quits. Moving the app to the Trash leaves the container behind until macOS or the user removes it.

## Rules for future features

- **Handoff between Macs:** data stays on the local network, between Macs the user linked. It must be documented here before release.
- **Updates:** checking for updates sends the requesting IP address to the update server. This must be off until the user turns it on, and must be documented here before release.
