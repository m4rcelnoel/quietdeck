/// Decides when a low battery is worth mentioning.
///
/// Each threshold fires once while the level falls. It's armed again only after the level
/// rose clearly above it, so a reading that jitters around a threshold stays quiet.
public struct BatteryAlertMonitor: Sendable {
    private let thresholds: [Int]
    private let rearmMargin: Int
    private var fired: Set<Int> = []

    public init(thresholds: [Int] = [20, 10], rearmMargin: Int = 5) {
        self.thresholds = thresholds.sorted()
        self.rearmMargin = rearmMargin
    }

    /// Takes a new reading. Returns the threshold to report, or `nil`.
    public mutating func update(percent: Int) -> Int? {
        for threshold in fired where percent >= threshold + rearmMargin {
            fired.remove(threshold)
        }

        let crossed = thresholds.filter { percent <= $0 }
        defer { fired.formUnion(crossed) }

        // Starting at 8 % reports the lowest threshold only, not every one on the way.
        guard let lowest = crossed.first, !fired.contains(lowest) else { return nil }
        return lowest
    }
}
