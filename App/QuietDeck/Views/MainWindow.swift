import QuietDeckCore
import SwiftUI

/// A page of the main window.
enum WindowSection: Hashable {
    case device(DeviceSection)
    case settings
    case about

    var title: LocalizedStringKey {
        switch self {
        case .device(let section): return section.title
        case .settings: return "Settings"
        case .about: return "About QuietDeck"
        }
    }
}

/// The one window of the app. Settings and About are pages here, like in System Settings.
struct MainWindow: View {
    let app: AppModel
    var initialSection: WindowSection?

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isCompact = false
    @Environment(\.usesPlainSurfaces) private var usesPlainSurfaces

    private var controller: DeviceController? {
        app.availability == .ready ? app.controller : nil
    }

    private var deviceSections: [DeviceSection] {
        controller?.capabilities.sections ?? []
    }

    private var allSections: [WindowSection] {
        deviceSections.map(WindowSection.device) + [.settings, .about]
    }

    var body: some View {
        @Bindable var app = app
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } detail: {
            detail
                .toolbar {
                    if isCompact {
                        ToolbarItem(placement: .principal) { compactPicker }
                    }
                }
        }
        .frame(minWidth: 420, minHeight: 480)
        .onGeometryChange(for: Bool.self) {
            $0.size.width < 520
        } action: { compact in
            isCompact = compact
            columnVisibility = compact ? .detailOnly : .all
        }
        .onChange(of: deviceSections) {
            if case .device(let section) = app.selectedSection, !deviceSections.isEmpty,
                !deviceSections.contains(section)
            {
                app.selectedSection = .device(.device)
            }
        }
        .onAppear {
            if let initialSection {
                app.selectedSection = initialSection
            }
        }
        .background { sectionShortcuts }
    }

    /// Command-1 and up jump to the sections.
    private var sectionShortcuts: some View {
        ForEach(Array(allSections.prefix(9).enumerated()), id: \.offset) { index, section in
            Button(section.title) { app.selectedSection = section }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                .hidden()
        }
    }

    private var sidebar: some View {
        @Bindable var app = app
        return List(selection: $app.selectedSection) {
            if let controller {
                deviceHeader(controller)
                Section {
                    ForEach(deviceSections, id: \.self) { section in
                        Label(section.title, systemImage: section.symbol)
                            .tag(WindowSection.device(section))
                    }
                }
            }
            Section {
                Label("Settings", systemImage: "gearshape")
                    .tag(WindowSection.settings)
                Label("About QuietDeck", systemImage: "info.circle")
                    .tag(WindowSection.about)
            }
        }
        .scrollContentBackground(usesPlainSurfaces ? .hidden : .automatic)
    }

    private func deviceHeader(_ controller: DeviceController) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "headphones")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(.tint, in: .rect(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 1) {
                Text(controller.state.name ?? String(localized: "Headphones"))
                    .font(.headline)
                    .lineLimit(1)
                Text(controller.statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .selectionDisabled()
        .padding(.bottom, 8)
    }

    private var compactPicker: some View {
        @Bindable var app = app
        return Picker("Section", selection: $app.selectedSection) {
            ForEach(allSections, id: \.self) { section in
                Text(section.title).tag(section)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch app.selectedSection {
        case .device(let section):
            if let controller, app.phase != .connectionFailed {
                page { deviceContent(section, controller) }
                    .toolbar { batteryItem(controller) }
            } else {
                UnavailableContent(app: app)
                    .navigationTitle(app.selectedSection.title)
            }
        case .settings:
            page { SettingsPage(app: app) }
        case .about:
            page { AboutPage(app: app) }
        }
    }

    private func page(@ViewBuilder content: () -> some View) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                content()
            }
            .padding(20)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(app.selectedSection.title)
    }

    @ViewBuilder
    private func deviceContent(_ section: DeviceSection, _ controller: DeviceController) -> some View {
        if controller.phase != .connected {
            connectionNote(controller)
        }
        Group {
            switch section {
            case .listening:
                ListeningSection(controller: controller, isCompact: isCompact)
            case .sound:
                SoundSection(controller: controller, presets: app.presets)
            case .sources:
                SourcesSection(controller: controller)
            case .device:
                DeviceInfoSection(controller: controller)
            }
        }
        .disabled(controller.phase != .connected)
    }

    @ToolbarContentBuilder
    private func batteryItem(_ controller: DeviceController) -> some ToolbarContent {
        if controller.capabilities.battery != nil, let battery = controller.state.battery {
            ToolbarItem(placement: .primaryAction) {
                BatteryBadge(battery: battery)
            }
        }
    }

    private func connectionNote(_ controller: DeviceController) -> some View {
        HStack(spacing: 8) {
            if controller.phase == .connecting {
                ProgressView()
                    .controlSize(.small)
            }
            Text(controller.statusText)
            Spacer()
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
    }
}

extension DeviceSection {
    var title: LocalizedStringKey {
        switch self {
        case .listening: return "Listening"
        case .sound: return "Sound"
        case .sources: return "Sources"
        case .device: return "Device"
        }
    }

    var symbol: String {
        switch self {
        case .listening: return "slider.horizontal.3"
        case .sound: return "slider.vertical.3"
        case .sources: return "arrow.left.arrow.right"
        case .device: return "headphones"
        }
    }
}
