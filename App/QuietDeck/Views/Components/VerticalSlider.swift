import SwiftUI

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
