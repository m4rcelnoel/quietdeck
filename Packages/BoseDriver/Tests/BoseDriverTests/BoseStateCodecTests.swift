import QuietDeckCore
import Testing

@testable import BoseDriver

/// Payloads below were recorded from a QC Ultra 2 on firmware 10.12.14.
@Suite struct BoseStateCodecTests {
    @Test func decodesPresetsAndCustom() {
        #expect(BoseStateCodec.mode([0x02]) == .preset("immersion"))
        #expect(BoseStateCodec.mode([0xFF]) == .custom)
        #expect(BoseStateCodec.mode([0x04]) == .custom)
        #expect(BoseStateCodec.mode([]) == nil)
    }

    @Test func recordedModesDecodeToTheirSettings() throws {
        let aware = try #require(BoseStateCodec.audioSettings([0x0A, 0, 0, 0, 1]))
        #expect(BoseStateCodec.noiseLevel(aware) == 0)
        #expect(BoseStateCodec.spatialMode(aware) == .off)

        let quiet = try #require(BoseStateCodec.audioSettings([0, 0, 0, 0, 1]))
        #expect(BoseStateCodec.noiseLevel(quiet) == 10)

        let immersion = try #require(BoseStateCodec.audioSettings([0, 0, 2, 0, 1]))
        #expect(BoseStateCodec.spatialMode(immersion) == .motion)

        let cinema = try #require(BoseStateCodec.audioSettings([0, 0, 1, 0, 1]))
        #expect(BoseStateCodec.spatialMode(cinema) == .still)
    }

    @Test func audioPayloadKeepsAutoCncAtZero() {
        let settings = BoseAudioSettings(cnc: 5, spatial: 1, wind: 1, anc: 1)
        #expect(settings.payload == [5, 0, 1, 1, 1])
    }

    @Test func noiseLevelRoundTrips() {
        for level in BoseStateCodec.noiseLevels {
            let settings = BoseAudioSettings(cnc: BoseStateCodec.cnc(forNoiseLevel: level), spatial: 0, wind: 0, anc: 1)
            #expect(BoseStateCodec.noiseLevel(settings) == level)
        }
    }

    @Test func rejectsImpossibleValues() {
        #expect(BoseStateCodec.audioSettings([1, 2, 3]) == nil)
        #expect(BoseStateCodec.noiseLevel(BoseAudioSettings(cnc: 11, spatial: 0, wind: 0, anc: 1)) == nil)
        #expect(BoseStateCodec.spatialMode(BoseAudioSettings(cnc: 0, spatial: 3, wind: 0, anc: 1)) == nil)
    }

    @Test func decodesRecordedEqualizer() {
        let bands = BoseStateCodec.equalizer([0xF6, 0x0A, 0x01, 0, 0xF6, 0x0A, 0xFF, 1, 0xF6, 0x0A, 0x01, 2])
        #expect(bands?.map(\.value) == [1, -1, 1])
        #expect(bands?.map(\.id) == [0, 1, 2])
    }

    @Test func encodesNegativeEqualizerValues() {
        #expect(BoseStateCodec.equalizerPayload(band: 0, value: -10) == [0xF6, 0])
    }

    @Test func rejectsMalformedEqualizer() {
        #expect(BoseStateCodec.equalizer([]) == nil)
        #expect(BoseStateCodec.equalizer([1, 2, 3]) == nil)
    }

    @Test func decodesRecordedBattery() {
        #expect(BoseStateCodec.batteryPercent([0x5A, 0xFF, 0xFF, 0]) == 90)
        #expect(BoseStateCodec.batteryPercent([0xC8]) == nil)
    }

    @Test func multipointUsesBitZero() {
        #expect(BoseStateCodec.multipoint([0x07]) == true)
        #expect(BoseStateCodec.multipoint([0x06]) == false)
        #expect(BoseStateCodec.multipoint([]) == nil)
    }

    @Test func decodesNameAndFirmware() {
        #expect(BoseStateCodec.name([0] + Array("Bose QC Ultra 2 HP".utf8)) == "Bose QC Ultra 2 HP")
        #expect(BoseStateCodec.firmware(Array("10.12.14+gde0210e".utf8)) == "10.12.14+gde0210e")
        #expect(BoseStateCodec.firmware(Array("1.0".utf8) + [0, 0]) == "1.0")
    }

    @Test func readsNameAtFixedOffsetEvenIfStatusLooksLikeAMarker() {
        let payload: [UInt8] = [1, 2, 3, 4, 5, 6, 0x03, 0x01, 0x01] + Array("Studio".utf8)
        let info = BoseStateCodec.deviceInfo(payload)
        #expect(info?.name == "Studio")
        #expect(info?.isConnected == true)
        #expect(info?.kind == .computer)
    }

    @Test func decodesOtherDeviceStates() {
        let phone = BoseStateCodec.deviceInfo([1, 2, 3, 4, 5, 6, 0, 2, 3] + Array("Phone".utf8))
        #expect(phone?.isConnected == false)
        #expect(phone?.kind == .phone)
        #expect(BoseStateCodec.deviceInfo([1, 2, 3]) == nil)
    }

    @Test func activeAddressNeedsABluetoothSource() {
        #expect(BoseStateCodec.activeAddress([0, 0x0F, 1, 1, 2, 3, 4, 5, 6]) == [1, 2, 3, 4, 5, 6])
        #expect(BoseStateCodec.activeAddress([0, 0x0F, 2]) == nil)
        #expect(BoseStateCodec.activeAddress([0, 0x0F, 2, 1, 2, 3, 4, 5, 6]) == nil)
    }

    @Test func recordedDeviceListBytesShowConnecting() {
        #expect(BoseStateCodec.isConnecting([0x05, 1, 2]))
        #expect(!BoseStateCodec.isConnecting([0x03, 1, 2]))
        #expect(!BoseStateCodec.isConnecting([0x01, 1, 2]))
        #expect(!BoseStateCodec.isConnecting([]))
    }

    @Test func sourceIDRoundTrips() {
        let address: [UInt8] = [0x0A, 0xBC, 0, 1, 2, 0xFF]
        let id = BoseStateCodec.sourceID(address)
        #expect(id == "0A:BC:00:01:02:FF")
        #expect(BoseStateCodec.address(fromSourceID: id) == address)
        #expect(BoseStateCodec.address(fromSourceID: "nonsense") == nil)
    }

    @Test func activeSourceDecidesStatus() {
        let first = BoseDeviceInfo(
            address: [1, 1, 1, 1, 1, 1], isConnected: true, kind: .computer, name: "A")
        let second = BoseDeviceInfo(
            address: [2, 2, 2, 2, 2, 2], isConnected: true, kind: .computer, name: "B")
        let third = BoseDeviceInfo(
            address: [3, 3, 3, 3, 3, 3], isConnected: false, kind: .phone, name: "C")
        let list = BoseStateCodec.sourceList(devices: [first, second, third], activeAddress: second.address)
        #expect(list.sources.map(\.status) == [.connected, .active, .remembered])
    }
}
