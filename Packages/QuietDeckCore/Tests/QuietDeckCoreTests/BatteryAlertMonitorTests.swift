import Testing

@testable import QuietDeckCore

@Suite struct BatteryAlertMonitorTests {
    @Test func staysQuietAboveTheThresholds() {
        var monitor = BatteryAlertMonitor()
        #expect(monitor.update(percent: 90) == nil)
        #expect(monitor.update(percent: 21) == nil)
    }

    @Test func firesOncePerThresholdWhileFalling() {
        var monitor = BatteryAlertMonitor()
        #expect(monitor.update(percent: 20) == 20)
        #expect(monitor.update(percent: 19) == nil)
        #expect(monitor.update(percent: 11) == nil)
        #expect(monitor.update(percent: 10) == 10)
        #expect(monitor.update(percent: 5) == nil)
    }

    @Test func startingLowReportsOnlyTheLowestThreshold() {
        var monitor = BatteryAlertMonitor()
        #expect(monitor.update(percent: 8) == 10)
        #expect(monitor.update(percent: 8) == nil)
    }

    @Test func jitterAroundAThresholdStaysQuiet() {
        var monitor = BatteryAlertMonitor()
        #expect(monitor.update(percent: 20) == 20)
        #expect(monitor.update(percent: 21) == nil)
        #expect(monitor.update(percent: 20) == nil)
        #expect(monitor.update(percent: 24) == nil)
        #expect(monitor.update(percent: 20) == nil)
    }

    @Test func chargingArmsItAgain() {
        var monitor = BatteryAlertMonitor()
        #expect(monitor.update(percent: 20) == 20)
        #expect(monitor.update(percent: 60) == nil)
        #expect(monitor.update(percent: 20) == 20)
    }

    @Test func chargingPastOnlyTheLowerThresholdKeepsTheHigherOneQuiet() {
        var monitor = BatteryAlertMonitor()
        #expect(monitor.update(percent: 9) == 10)
        #expect(monitor.update(percent: 16) == nil)
        #expect(monitor.update(percent: 10) == 10)
    }
}
