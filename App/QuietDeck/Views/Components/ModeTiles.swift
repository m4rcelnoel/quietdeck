import QuietDeckCore
import SwiftUI

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
