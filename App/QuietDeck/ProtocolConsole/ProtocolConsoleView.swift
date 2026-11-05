import QuietDeckCore
import SwiftUI
import UniformTypeIdentifiers

struct ProtocolConsoleView: View {
    @Bindable var model: ProtocolConsoleModel

    var body: some View {
        VSplitView {
            log
                .frame(minHeight: 220)
            HSplitView {
                composer
                    .frame(minWidth: 320)
                history
                    .frame(minWidth: 260)
            }
            .frame(minHeight: 200)
        }
        .frame(minWidth: 760, minHeight: 520)
        .toolbar { toolbar }
        .safeAreaInset(edge: .bottom) { footer }
        .confirmationDialog(
            "Send this frame?",
            isPresented: Binding(
                get: { model.pendingConfirmation != nil },
                set: { if !$0 { model.pendingConfirmation = nil } }
            ),
            presenting: model.pendingConfirmation
        ) { _ in
            Button("Send") { Task { await model.confirmPending() } }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(pending.reason)
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            TextField("Filter", text: $model.filter)
                .frame(width: 140)
            Toggle("Pause", isOn: $model.isPaused)
            Button("Clear", action: model.clear)
            Menu("Export") {
                Toggle("Redact addresses and names", isOn: $model.redactExports)
                Button("As text…") { model.export(as: .plainText) }
                Button("As JSON…") { model.export(as: .json) }
            }
        }
    }

    private var log: some View {
        Table(model.visibleRows) {
            TableColumn("Time") { Text($0.time).monospacedDigit() }
                .width(70)
            TableColumn("") { Text($0.direction) }
                .width(20)
            TableColumn("Frame") { Text($0.entry.summary) }
                .width(min: 140, ideal: 200)
            TableColumn("Hex") { Text($0.hex).font(.body.monospaced()).textSelection(.enabled) }
        }
    }

    private var composer: some View {
        Form {
            ForEach(model.composer?.fields ?? [], id: \.id) { field in
                if let choices = field.choices {
                    Picker(field.label, selection: binding(for: field.id)) {
                        ForEach(choices, id: \.self) { Text($0).tag($0) }
                    }
                } else {
                    TextField(field.label, text: binding(for: field.id))
                        .font(.body.monospaced())
                }
            }
            LabeledContent("Frame") {
                Text(model.draftFrame.map { FrameLogExport.hex($0.bytes) } ?? "Invalid")
                    .font(.body.monospaced())
            }
            if case .deny(let reason) = model.draftVerdict {
                Label(reason, systemImage: "hand.raised")
                    .foregroundStyle(.red)
            }
            Button("Send") { Task { await model.sendDraft() } }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canSend)
        }
        .formStyle(.grouped)
    }

    private var canSend: Bool {
        guard let verdict = model.draftVerdict else { return false }
        if case .deny = verdict { return false }
        return true
    }

    private var history: some View {
        List($model.history) { $item in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.hex)
                        .font(.body.monospaced())
                    Spacer()
                    Button("Resend") {
                        let frame = item.frame
                        Task { await model.send(frame) }
                    }
                }
                TextField("Note", text: $item.note)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Raw frames can change device state.", systemImage: "exclamationmark.triangle")
            Text(model.status)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func binding(for id: String) -> Binding<String> {
        Binding(
            get: { model.values[id] ?? "" },
            set: { model.values[id] = $0 }
        )
    }
}
