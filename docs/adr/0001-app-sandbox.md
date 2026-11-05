# 1. Ship with App Sandbox enabled

Status: accepted

## Context

QuietDeck is distributed outside the Mac App Store, so App Sandbox is optional. It needs IOBluetooth RFCOMM access and, later, Bonjour and local network connections.

## Decision

Enable App Sandbox with the Bluetooth, network client and network server entitlements.

## Evidence

A sandboxed build opened RFCOMM channel 2 on a QC Ultra 2 and completed 100 battery reads with no failures. Latency matched the non-sandboxed build.

## Consequences

- The app gains system-level isolation at no measured cost.
- Files the app writes, including diagnostics logs, live in its container.
- Revisit this if CoreAudio output routing or Bluetooth connection control needed for handoff turns out to be blocked.
