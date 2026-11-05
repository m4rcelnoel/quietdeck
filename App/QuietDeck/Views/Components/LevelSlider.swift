import QuietDeckCore
import SwiftUI

/// An integer slider that only reports real changes.
struct LevelSlider: View {
    let value: Int
    let range: ClosedRange<Int>
    let label: LocalizedStringKey
    let onChange: (Int) -> Void

    var body: some View {
        Slider(
            value: Binding(
                get: { Double(value) },
                set: { newValue in
                    let rounded = Int(newValue.rounded())
                    if rounded != value {
                        onChange(rounded)
                    }
                }
            ),
            in: Double(range.lowerBound)...Double(range.upperBound),
            step: 1
        ) {
            Text(label)
        }
        .labelsHidden()
        .accessibilityValue(Text("\(value) of \(range.upperBound)"))
    }
}

/// The noise level with its value. Wind Block masks noise control, so it's off meanwhile.
struct NoiseLevelControl: View {
    let controller: DeviceController
    let level: Int
    let range: ClosedRange<Int>

    var body: some View {
        LevelSlider(value: level, range: range, label: "Noise control") {
            controller.setNoiseLevel($0)
        }
        .disabled(controller.isNoiseControlMasked)
        Text("\(level)")
            .monospacedDigit()
            .frame(width: 22, alignment: .trailing)
    }
}
