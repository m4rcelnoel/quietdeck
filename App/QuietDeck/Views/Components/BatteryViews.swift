import QuietDeckCore
import SwiftUI

struct BatteryRing: View {
    let battery: BatteryStatus?
    var size: CGFloat = 44

    private var color: Color {
        guard let percent = battery?.percent else { return .secondary }
        if percent < 10 { return .red }
        return percent < 20 ? .orange : .green
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 4)
            Circle()
                .trim(from: 0, to: CGFloat(battery?.percent ?? 0) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(battery.map { "\($0.percent)" } ?? "–")
                .font(.system(size: size * 0.28, weight: .semibold))
                .monospacedDigit()
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("Battery")
        .accessibilityValue(battery.map { Text("\($0.percent) percent") } ?? Text("Unknown"))
    }
}

/// The battery level for the toolbar. It sets its own size, because a plain label gets
/// squeezed into the toolbar's capsule.
struct BatteryBadge: View {
    let battery: BatteryStatus

    private var symbol: String {
        switch battery.percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(battery.percent < 20 ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
            Text("\(battery.percent) %")
                .monospacedDigit()
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery")
        .accessibilityValue(Text("\(battery.percent) percent"))
    }
}
