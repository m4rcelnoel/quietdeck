public enum DeviceCommand: Sendable, Equatable {
    case setMode(ListeningMode.ID)
    /// Values left `nil` stay as they are on the device.
    case setAudio(noiseLevel: Int?, spatial: SpatialAudioMode?, windBlock: Bool?)
    case setEqualizerBand(id: EqualizerBand.ID, value: Int)
    case setMultipoint(Bool)
    case switchSource(AudioSource.ID)
    /// Asks the headphones to connect a remembered device. This only starts the attempt.
    case connectSource(AudioSource.ID)
    /// Pauses whatever the active source is playing.
    case pausePlayback
    case rename(String)
}

/// Something the device reported without being asked, or a change in the connection.
///
/// `connect()` reports its own outcome by returning or throwing, so drivers must not send
/// `.connecting` for it: `.connecting` means an established connection was lost.
public enum DeviceEvent: Sendable, Equatable {
    case connectionChanged(ConnectionState)
    case stateChanged(DeviceState)
    case capabilitiesChanged(DeviceCapabilities)
}

public enum ConnectionState: Sendable, Equatable {
    case disconnected, connecting, connected
}

public enum DriverError: Error, Sendable, Equatable {
    case notConnected
    case unsupported
    case timeout
    /// Another process holds the device's control channel.
    case busy
    /// The device needs manufacturer authentication for this. Never retried.
    case authenticationRequired
    /// The device refused the command, with its driver-specific reason.
    case rejected(code: Int, reason: String)
    case malformedResponse
    case transportFailed(String)
}
