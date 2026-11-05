import QuietDeckCore
import SwiftUI

struct ListeningSection: View {
    let controller: DeviceController
    let isCompact: Bool

    private var capabilities: DeviceCapabilities {
        controller.capabilities
    }

    private var state: DeviceState {
        controller.state
    }

    var body: some View {
        if capabilities.listeningModes != nil {
            hero
            ModeTiles(controller: controller, columns: isCompact ? 2 : 4)
            ProblemNote(controller: controller, controls: [.mode])
        }
        if capabilities.noiseControl != nil || capabilities.spatialAudio != nil || capabilities.windBlock != nil {
            settings
        }
        if capabilities.audioSources != nil, let active = state.sources?.active {
            DeckGroup {
                DeckRow {
                    Image(systemName: active.kind.symbol)
                        .foregroundStyle(.secondary)
                    Text(active.id == controller.localSourceID ? "Playing on this Mac" : "Playing on \(active.name)")
                        .lineLimit(1)
                    Spacer()
                }
            }
        }
    }

    private var hero: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(controller.modeTitle)
                    .font(.title2.weight(.semibold))
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if capabilities.battery != nil {
                BatteryRing(battery: state.battery)
            }
        }
        .padding(14)
        .glassSurface(cornerRadius: 14)
    }

    private var summary: LocalizedStringKey {
        let modes = capabilities.listeningModes?.modes ?? []
        if case .preset(let id) = state.mode, let mode = modes.first(where: { $0.id == id }) {
            return mode.kind.summary
        }
        return "Your own noise and immersive settings"
    }

    private var settings: some View {
        DeckGroup {
            if let noise = capabilities.noiseControl, let level = state.noiseLevel {
                DeckRow {
                    Text("Noise control")
                    NoiseLevelControl(controller: controller, level: level, range: noise.range)
                }
            }
            ProblemNote(controller: controller, controls: [.noiseLevel])
            if let spatial = capabilities.spatialAudio, let current = state.spatialAudio {
                DeckRow {
                    Text("Immersive audio")
                    Spacer()
                    Picker(
                        "Immersive audio",
                        selection: Binding(get: { current }, set: { controller.setSpatialAudio($0) })
                    ) {
                        ForEach(spatial.options, id: \.self) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }
            ProblemNote(controller: controller, controls: [.spatialAudio])
            if capabilities.windBlock != nil, let wind = state.windBlock {
                SwitchRow(
                    title: "Wind block",
                    detail: wind ? "Noise control has no effect while this is on." : nil,
                    isOn: Binding(get: { wind }, set: { controller.setWindBlock($0) })
                )
            }
            ProblemNote(controller: controller, controls: [.windBlock])
        }
    }
}

extension SpatialAudioMode {
    var title: LocalizedStringKey {
        switch self {
        case .off: return "Off"
        case .still: return "Still"
        case .motion: return "Motion"
        }
    }
}
