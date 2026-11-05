import SwiftUI

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

/// A `DeckRow` with a title, an optional explanation and a switch.
struct SwitchRow: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?
    @Binding var isOn: Bool

    var body: some View {
        DeckRow {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}
