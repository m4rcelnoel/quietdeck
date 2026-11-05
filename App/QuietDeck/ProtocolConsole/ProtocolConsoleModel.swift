import AppKit
import Observation
import QuietDeckCore
import UniformTypeIdentifiers

/// State of the Protocol Console. Contains no vendor knowledge.
@MainActor
@Observable
final class ProtocolConsoleModel {
    struct Row: Identifiable {
        let id: Int
        let entry: FrameLogEntry
        var time: String { String(format: "%.3f", entry.secondsSinceSessionStart) }
        var direction: String { FrameLogExport.arrow(entry.direction) }
        var hex: String { FrameLogExport.hex(entry.bytes) }
    }

    struct HistoryItem: Identifiable {
        let id = UUID()
        let frame: RawFrame
        var note = ""
        var hex: String { FrameLogExport.hex(frame.bytes) }
    }

    private(set) var rows: [Row] = []
    private(set) var status = ""
    private(set) var composer: FrameComposerSpec?
    var history: [HistoryItem] = []
    var filter = ""
    var isPaused = false
    var values: [String: String] = [:]
    var pendingConfirmation: (frame: RawFrame, reason: String)?
    var redactExports = true

    private var console: (any RawFrameConsole)?
    private var listener: Task<Void, Never>?
    private var nextRowID = 0

    var visibleRows: [Row] {
        guard !filter.isEmpty else { return rows }
        return rows.filter {
            $0.entry.summary.localizedCaseInsensitiveContains(filter) || $0.hex.contains(filter.lowercased())
        }
    }

    var draftFrame: RawFrame? {
        console?.frame(from: values)
    }

    var draftVerdict: RawFrameVerdict? {
        draftFrame.flatMap { console?.evaluate($0) }
    }

    /// Connects to the app's one session. Traffic is logged from here on.
    func attach(_ console: (any RawFrameConsole)?) {
        self.console = console
        composer = console?.composer
        for field in composer?.fields ?? [] where values[field.id] == nil {
            values[field.id] = field.choices?.first ?? ""
        }
        listener?.cancel()
        guard let traffic = console?.traffic else { return }
        listener = Task { [weak self] in
            for await entry in traffic {
                self?.append(entry)
            }
        }
    }

    /// Sends the draft, asking first if the driver's policy requires it.
    func sendDraft() async {
        guard let frame = draftFrame else { return }
        await send(frame)
    }

    func send(_ frame: RawFrame) async {
        switch console?.evaluate(frame) {
        case .allow:
            await transmit(frame)
        case .confirm(let reason):
            pendingConfirmation = (frame, reason)
        case .deny(let reason):
            status = reason
        case nil:
            break
        }
    }

    func confirmPending() async {
        guard let pending = pendingConfirmation else { return }
        pendingConfirmation = nil
        await transmit(pending.frame)
    }

    private func transmit(_ frame: RawFrame) async {
        if history.first?.frame != frame {
            history.insert(HistoryItem(frame: frame), at: 0)
        }
        do {
            try await console?.send(frame)
        } catch {
            status = "No valid answer: \(error)"
        }
    }

    func clear() {
        rows = []
    }

    func export(as type: UTType) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = "quietdeck-frames"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        var entries = rows.map(\.entry)
        if redactExports, let console {
            entries = entries.map(console.redacted)
        }
        do {
            let data = type == .json ? try FrameLogExport.json(entries) : Data(FrameLogExport.text(entries).utf8)
            try data.write(to: url)
        } catch {
            status = "Couldn't save the log."
        }
    }

    private func append(_ entry: FrameLogEntry) {
        guard !isPaused else { return }
        rows.append(Row(id: nextRowID, entry: entry))
        nextRowID += 1
    }
}
