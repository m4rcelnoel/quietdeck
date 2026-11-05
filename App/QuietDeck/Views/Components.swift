import QuietDeckCore
import SwiftUI

extension ListeningMode.Kind {
    var symbol: String {
        switch self {
        case .quiet: return "moon.fill"
        case .aware: return "ear"
        case .immersion: return "sparkles"
        case .cinema: return "film"
        case .other: return "slider.horizontal.3"
        }
    }

    var summary: LocalizedStringKey {
        switch self {
        case .quiet: return "Full noise cancellation"
        case .aware: return "Hear the world around you"
        case .immersion: return "Spatial sound that follows you"
        case .cinema: return "Wide sound for film"
        case .other: return "A mode from your headphones"
        }
    }
}

extension AudioSource.Kind {
    var symbol: String {
        switch self {
        case .computer: return "laptopcomputer"
        case .phone: return "iphone"
        case .tablet: return "ipad"
        case .auxiliary: return "cable.connector"
        case .unknown: return "dot.radiowaves.left.and.right"
        }
    }
}

extension EnvironmentValues {
    /// Set by the snapshot renderer, which can't draw system materials.
    @Entry var usesPlainSurfaces = false
}

/// Liquid Glass on macOS 26 and later, a standard fill before that.
private struct GlassSurface: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?

    @Environment(\.usesPlainSurfaces) private var usesPlainSurfaces
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !usesPlainSurfaces, !reduceTransparency, contrast != .increased {
            content.glassEffect(.regular.tint(tint).interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(
                    tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.quaternary),
                    in: .rect(cornerRadius: cornerRadius)
                )
                .overlay {
                    if contrast == .increased {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(.primary.opacity(0.6))
                    }
                }
        }
    }
}

extension View {
    func glassSurface(cornerRadius: CGFloat, tint: Color? = nil) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius, tint: tint))
    }
}

/// A rounded group of rows, like a section in System Settings.
struct DeckGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(.quaternary.opacity(0.5))
        .clipShape(.rect(cornerRadius: 12))
    }
}

/// A row in a `DeckGroup`. Its separator sits just above it, so the group's rounded
/// clipping hides the first one.
struct DeckRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 12) {
            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(minHeight: 44)
        .overlay(alignment: .top) {
            Divider()
                .offset(y: -1)
                .padding(.leading, 14)
        }
    }
}

/// The mode buttons. Tiles keep their labels on one line and reflow as width allows.
struct ModeTiles: View {
    enum Style {
        case stacked, inline
    }

    let controller: DeviceController
    var style: Style = .stacked
    var columns = 4

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let modes = controller.capabilities.listeningModes?.modes ?? []
        // Fewer modes than columns fill the row, so small devices don't look unfinished.
        let count = max(1, min(columns, modes.count))
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: count), spacing: 8) {
            ForEach(modes) { mode in
                tile(mode)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Listening mode")
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: controller.state.mode)
    }

    private func tile(_ mode: ListeningMode) -> some View {
        let isSelected = controller.state.mode == .preset(mode.id)
        return Button {
            controller.selectMode(mode.id)
        } label: {
            label(mode)
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .frame(maxWidth: .infinity, minHeight: style == .stacked ? 64 : 44)
                .contentShape(.rect(cornerRadius: 12))
                .glassSurface(cornerRadius: 12, tint: isSelected ? .accentColor : nil)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(LocalizedStringKey(mode.name))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func label(_ mode: ListeningMode) -> some View {
        switch style {
        case .stacked:
            VStack(spacing: 6) {
                Image(systemName: mode.kind.symbol)
                    .font(.title3)
                    .frame(height: 24)
                Text(LocalizedStringKey(mode.name))
                    .font(.callout)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        case .inline:
            HStack(spacing: 8) {
                Image(systemName: mode.kind.symbol)
                    .frame(width: 20)
                Text(LocalizedStringKey(mode.name))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
        }
    }
}

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

/// A short inline note about a failed command, shown next to its control.
struct ProblemNote: View {
    let controller: DeviceController
    let controls: [DeviceController.Control]

    var body: some View {
        if let problem = controller.problem, controls.contains(problem.control) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message(problem))
                Spacer()
            }
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private func message(_ problem: DeviceController.Problem) -> LocalizedStringKey {
        switch (problem.kind, problem.control) {
        case (.notAvailable, _):
            return "Not available on this firmware."
        case (.failed, .connection):
            return "Couldn't connect. Check that the device is on and its Bluetooth is turned on."
        case (.failed, .source):
            return "Couldn't bring audio here. Try again in a moment."
        case (.failed, _):
            return "Couldn't apply that. Your headphones keep their last setting."
        }
    }
}

extension DeviceController {
    var statusText: LocalizedStringKey {
        switch phase {
        case .connected: return "Connected"
        case .connecting: return "Connecting…"
        case .disconnected: return "Not connected"
        case .connectionFailed: return "Couldn't connect"
        }
    }

    var modeTitle: LocalizedStringKey {
        modeName.map { LocalizedStringKey($0) } ?? "Custom"
    }

    var modeName: String? {
        switch state.mode {
        case .preset(let id):
            return capabilities.listeningModes?.modes.first { $0.id == id }?.name
        case .custom, nil:
            return nil
        }
    }
}

/// A full-size message for when there's nothing to control.
struct UnavailableContent: View {
    let app: AppModel

    var body: some View {
        switch app.availability {
        case .checking:
            ProgressView()
        case .bluetoothOff:
            message(
                "Bluetooth is off",
                systemImage: "exclamationmark.triangle",
                detail: "Turn on Bluetooth to use your headphones.",
                settingsPane: "Open Bluetooth Settings"
            )
        case .noDevice:
            message(
                "No supported headphones found",
                systemImage: "headphones",
                detail: "Pair your headphones in System Settings first.",
                settingsPane: "Open Bluetooth Settings"
            )
        case .ready:
            ContentUnavailableView {
                Label("Couldn't connect", systemImage: "headphones")
            } description: {
                Text("Check that your headphones are on and that no other app is using them.")
            } actions: {
                Button("Try again") { Task { await app.retry() } }
            }
        }
    }

    private func message(
        _ title: LocalizedStringKey,
        systemImage: String,
        detail: LocalizedStringKey,
        settingsPane: LocalizedStringKey
    ) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(detail)
        } actions: {
            Button(settingsPane) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Check again") { Task { await app.retry() } }
        }
    }
}
