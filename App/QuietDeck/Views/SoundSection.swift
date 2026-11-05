import QuietDeckCore
import SwiftUI

struct SoundSection: View {
    let controller: DeviceController
    let presets: EqualizerPresetStore

    @State private var isNaming = false
    @State private var draftName = ""
    @State private var renaming: EqualizerPreset?

    private var bands: [EqualizerBandValue] {
        controller.state.equalizer ?? []
    }

    private var currentPreset: EqualizerPreset? {
        presets.preset(matching: bands)
    }

    var body: some View {
        if let equalizer = controller.capabilities.equalizer {
            DeckGroup {
                DeckRow {
                    Text("Preset")
                    Spacer()
                    presetMenu(equalizer)
                }
            }
            bandSliders(equalizer)
            ProblemNote(controller: controller, controls: [.equalizer])
        }
    }

    private func presetMenu(_ equalizer: EqualizerCapability) -> some View {
        Menu(currentPreset?.name ?? (isFlat ? String(localized: "Flat") : String(localized: "Edited"))) {
            Button("Flat") { apply(values: [:], equalizer) }
            ForEach(presets.presets) { preset in
                Button(preset.name) { apply(values: preset.values, equalizer) }
            }
            Divider()
            Button("Save as preset…") {
                draftName = ""
                isNaming = true
            }
            if let preset = currentPreset {
                Button("Rename “\(preset.name)”…") {
                    draftName = preset.name
                    renaming = preset
                    isNaming = true
                }
                Button("Delete “\(preset.name)”", role: .destructive) {
                    presets.delete(preset.id)
                }
            }
        }
        .fixedSize()
        .alert(renaming == nil ? "Save preset" : "Rename preset", isPresented: $isNaming) {
            TextField("Name", text: $draftName)
            Button("Save") { commitName() }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    private var isFlat: Bool {
        bands.allSatisfy { $0.value == 0 }
    }

    private func commitName() {
        let name = draftName.trimmingCharacters(in: .whitespaces)
        defer { renaming = nil }
        guard !name.isEmpty else { return }
        if let renaming {
            presets.rename(renaming.id, to: name)
        } else {
            presets.save(name: name, bands: bands)
        }
    }

    private func apply(values: [Int: Int], _ equalizer: EqualizerCapability) {
        for band in equalizer.bands {
            controller.setEqualizerBand(band.id, value: values[band.id] ?? 0)
        }
    }

    private func bandSliders(_ equalizer: EqualizerCapability) -> some View {
        HStack(spacing: 0) {
            ForEach(equalizer.bands) { band in
                VerticalBand(
                    band: band,
                    value: bands.first { $0.id == band.id }?.value ?? 0,
                    range: equalizer.level.range
                ) {
                    controller.setEqualizerBand(band.id, value: $0)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 16)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
    }
}

/// A native vertical slider. SwiftUI's `Slider` has no vertical style, and rotating one
/// only turns its drawing: the mouse still works along the original axis.
struct VerticalSlider: NSViewRepresentable {
    let value: Int
    let range: ClosedRange<Int>
    let label: String
    let onChange: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(
            value: Double(value),
            minValue: Double(range.lowerBound),
            maxValue: Double(range.upperBound),
            target: context.coordinator,
            action: #selector(Coordinator.changed(_:))
        )
        slider.isVertical = true
        slider.isContinuous = true
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.value = value
        context.coordinator.onChange = onChange
        slider.setAccessibilityLabel(label)
        // While dragging, the mouse decides. Setting the value would make the knob jump.
        if NSEvent.pressedMouseButtons == 0 {
            slider.doubleValue = Double(value)
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var value = 0
        var onChange: (Int) -> Void = { _ in }

        @objc func changed(_ slider: NSSlider) {
            let rounded = Int(slider.doubleValue.rounded())
            if rounded != value {
                value = rounded
                onChange(rounded)
            }
        }
    }
}

private struct VerticalBand: View {
    private static let height: CGFloat = 190

    let band: EqualizerBand
    let value: Int
    let range: ClosedRange<Int>
    let onChange: (Int) -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text(value > 0 ? "+\(value)" : "\(value)")
                .monospacedDigit()
                .fontWeight(.medium)
            VerticalSlider(value: value, range: range, label: band.name, onChange: onChange)
                .frame(width: 28, height: Self.height)
            Text(LocalizedStringKey(band.name))
                .font(.callout)
        }
    }
}
