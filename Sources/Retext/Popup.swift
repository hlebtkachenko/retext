import AppKit
import Carbon.HIToolbox
import RetextCore
import SwiftUI

@MainActor
final class PopupModel: ObservableObject {
    enum Phase: Equatable {
        case menu
        case working(String)
        case done
        case message(String, isError: Bool, hint: String? = nil, symbol: String = "text.cursor")
    }

    @Published var phase = Phase.menu
    @Published var actions: [CustomAction] = []
    /// nil = the instruction field; otherwise the highlighted action button.
    @Published var selected: Int?
    @Published var instruction = ""
    @Published var above = false
    weak var field: NSTextField?
}

/// AppKit text field: it takes first responder reliably inside the non-activating panel.
struct InstructionField: NSViewRepresentable {
    @ObservedObject var model: PopupModel

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.placeholderString = "Edit as"
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = context.coordinator
        model.field = field
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != model.instruction { field.stringValue = model.instruction }
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let model: PopupModel
        init(model: PopupModel) { self.model = model }
        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            MainActor.assumeIsolated { model.instruction = field.stringValue }
        }
    }
}

struct PopupView: View {
    @ObservedObject var model: PopupModel
    let pick: (Int) -> Void
    @Namespace private var glass

    var body: some View {
        GlassEffectContainer {
            Group {
                switch model.phase {
                case .menu: menu
                case .working(let progress): status(progress, hint: "esc") { ProgressView().controlSize(.small) }
                case .done: status("Replaced", hint: "⌘Z to undo") { symbol("checkmark.circle.fill", .green) }
                case .message(let text, let isError, let hint, let name):
                    status(text, hint: hint) { symbol(isError ? "exclamationmark.triangle.fill" : name, isError ? .orange : .secondary) }
                }
            }
            .glassEffect(.regular, in: .capsule)
            .glassEffectID("pill", in: glass)
        }
        .font(.body)
        .padding(PopupController.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: model.above ? .bottomLeading : .topLeading)
        .animation(.smooth(duration: 0.25), value: model.phase)
    }

    private var menu: some View {
        HStack(spacing: 4) {
            InstructionField(model: model)
                .padding(.horizontal, 8)
                .frame(width: 104, height: 24)
                .background(Capsule().fill(Color.primary.opacity(model.selected == nil ? 0.08 : 0.04)))
            ForEach(Array(model.actions.enumerated()), id: \.element.id) { index, action in
                let isSelected = model.selected == index
                Button { pick(index) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: action.symbol).imageScale(.small)
                        Text(action.title)
                    }
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .foregroundStyle(isSelected ? .white : .primary)
                        .background(Capsule().fill(isSelected ? Color.accentColor : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .onHover { if $0, model.instruction.isEmpty { model.selected = index } }
            }
        }
        .padding(4)
    }

    private func status(_ text: String, hint: String? = nil, @ViewBuilder icon: () -> some View) -> some View {
        HStack(spacing: 8) {
            icon().frame(width: 16, height: 16)
            Text(text)
            if let hint { Text(hint).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
    }

    private func symbol(_ name: String, _ color: Color) -> some View {
        Image(systemName: name).foregroundStyle(color).imageScale(.medium)
    }
}

final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class PopupController {
    static let margin: CGFloat = 12          // transparent room around the glass for its shadow
    private static let gap: CGFloat = 8      // space between the selection and the glass

    private let model = PopupModel()
    private let runner = ClaudeRunner()
    private var panel: KeyPanel?
    private var selection: Selection?
    private var work: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var monitors: [Any] = []
    private var anchor: CGRect?

    /// ⌥Space opens the menu (or closes it); ⌥1…⌥9 pass an action index and run it straight away.
    func trigger(_ action: Int? = nil) {
        if panel?.isVisible == true, model.phase == .menu {
            // The menu is open: ⌥N runs on the selection already read; a second ⌘C would hit Retext's own field.
            guard let action else { return close() }
            return run(action)
        }
        guard work == nil else { return }
        Task {
            guard let selection = await SelectionIO.read() else {
                return flash(.message("Select text first", isError: false), near: nil, for: 1.5)
            }
            self.selection = selection
            model.actions = AppState.shared.settings.actions
            guard action ?? 0 < model.actions.count else { return }
            model.selected = nil
            model.instruction = ""
            model.phase = action.map { _ in .working("Working…") } ?? .menu
            show(near: selection.rect)
            if let action { run(action) }
        }
    }

    func demo(_ state: String) {
        model.actions = AppState.shared.settings.actions
        model.phase = switch state {
        case "working": .working("Translating to Czech…")
        case "done": .done
        case "error": .message("Claude didn't answer. Your text is unchanged.", isError: true)
        case "empty": .message("Select text first", isError: false)
        case "nochange": .message("No changes needed", isError: false, symbol: "checkmark.circle")
        default: .menu
        }
        let f = (NSScreen.main ?? NSScreen.screens.first)?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        show(near: CGRect(x: f.midX - 200, y: f.height / 2 - 20, width: 400, height: 18))
        if let panel {  // screencapture -R rectangle (top-left origin) for screenshots
            let r = panel.frame
            print("capture \(Int(r.minX)),\(Int(f.maxY - r.maxY)),\(Int(r.width)),\(Int(r.height))")
            fflush(stdout)
        }
    }

    // MARK: Flow

    private func run(_ index: Int) {
        guard let selection, work == nil, model.actions.indices.contains(index) else { return }
        let action = model.actions[index]
        let settings = AppState.shared.settings
        model.selected = index
        execute(Engine.job(for: action, text: selection.text, settings: settings, bundleID: selection.app.bundleIdentifier),
                progress: progress(for: action))
    }

    private func runInstruction() {
        let instruction = model.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let selection, !instruction.isEmpty else { return }
        execute(Engine.job(instruction: instruction, settings: AppState.shared.settings, bundleID: selection.app.bundleIdentifier),
                progress: "Working…")
    }

    private func progress(for action: CustomAction) -> String {
        switch action.kind {
        case .grammar: "Fixing grammar…"
        case .translate: "Translating to \(action.title)…"
        case .other: "\(action.title)…"
        }
    }

    private func execute(_ job: Job, progress: String) {
        guard let selection, work == nil else { return }
        hideTask?.cancel()
        model.phase = .working(progress)
        fit()
        work = Task {
            defer { work = nil }
            let timeout = Task { try await Task.sleep(for: .seconds(60)); runner.cancel() }
            defer { timeout.cancel() }
            do {
                let result = try await result(of: job, for: selection)
                if Engine.isUnchanged(input: selection.text, output: result) {
                    return flash(.message("No changes needed", isError: false, symbol: "checkmark.circle"), for: 1.5)
                }
                let final = keepOuterWhitespace(of: selection.text, around: result)
                if !selection.editable { return copy(final, note: "Copied to clipboard") }
                if !SelectionIO.stillSelected(selection) { return copy(final, note: "Selection changed. Copied.") }
                panel?.orderOut(nil)
                await SelectionIO.replace(in: selection.app, with: final, attributes: selection.attributes)
                flash(.done, for: 1.2)
            } catch {
                guard !Task.isCancelled, model.phase != .menu, panel?.isVisible == true else { return }
                let failure = error as? ClaudeFailure ?? .other("")
                if failure == .notFound { AppState.shared.claudeFound = false }
                flash(.message(failure.message, isError: true), for: failure == .other("") ? 3 : 5)
            }
        }
    }

    /// The cached result when model, prompt and text match an entry in the history; otherwise Claude's answer, recorded.
    /// With "Keep history" off, neither the cache nor the history is touched.
    private func result(of job: Job, for selection: Selection) async throws -> String {
        let state = AppState.shared
        let key = Engine.cacheKey(model: job.model, system: job.system, text: selection.text)
        let keep = state.settings.keepHistory
        if keep, let hit = state.history.lookup(key) {
            state.usage.recordHit()
            return hit.output
        }
        let output = try await runner.run(job, text: selection.text, claudePath: state.settings.claudePath)
        try Task.checkCancellation()
        state.usage.recordCall(model: job.model, output: output)
        if keep { state.history.add(HistoryEntry(key: key, appName: selection.app.localizedName ?? "", title: job.title,
                                       input: selection.text, output: output.text, model: job.model,
                                       inputTokens: output.inputTokens, outputTokens: output.outputTokens, costUSD: output.costUSD)) }
        return output.text
    }

    /// For text that can't be edited in place: copy the result; while the bubble shows, ⌘Z brings the old clipboard back.
    private func copy(_ text: String, note: String) {
        let restore = SelectionIO.copyRestorable(text)
        Hotkeys.undo = restore.map { restore in
            { [weak self] in
                restore()
                self?.flash(.message("Previous clipboard restored", isError: false, symbol: "arrow.uturn.backward"), for: 1.2)
            }
        }
        flash(.message(note, isError: false, hint: restore == nil ? nil : "⌘Z restores previous", symbol: "doc.on.clipboard"), for: 4)
    }

    private func cancel() {
        runner.cancel()
        work?.cancel()
        work = nil
        close()
    }

    private func keepOuterWhitespace(of original: String, around result: String) -> String {
        let leading = original.prefix { $0.isWhitespace || $0.isNewline }
        let trailing = original.reversed().prefix { $0.isWhitespace || $0.isNewline }.reversed()
        return leading + result + String(trailing)
    }

    // MARK: Window

    private func show(near rect: CGRect?) {
        hideTask?.cancel()
        let panel = self.panel ?? makePanel()
        anchor = rect
        panel.setFrame(frame(near: rect, size: fittingSize()), display: true)
        panel.alphaValue = 1
        panel.makeKeyAndOrderFront(nil)
        if model.phase == .menu, let field = model.field { panel.makeFirstResponder(field) }
        installMonitors()
    }

    /// The SwiftUI content's own size for the current phase.
    private func fittingSize() -> CGSize {
        panel?.contentView?.layoutSubtreeIfNeeded()
        return panel?.contentView?.fittingSize ?? .zero
    }

    /// After a phase change: grow the panel if the new content is wider, so nothing clips. It never shrinks while open,
    /// which keeps the capsule anchored while it animates.
    private func fit() {
        DispatchQueue.main.async { [self] in
            guard let panel, panel.isVisible else { return }
            let needed = fittingSize()
            let size = CGSize(width: max(needed.width, panel.frame.width), height: max(needed.height, panel.frame.height))
            if size != panel.frame.size { panel.setFrame(frame(near: anchor, size: size), display: true) }
        }
    }

    private func flash(_ phase: PopupModel.Phase, near rect: CGRect? = nil, for seconds: Double) {
        model.phase = phase
        if panel?.isVisible != true { show(near: rect) } else { fit() }
        panel?.orderFrontRegardless()
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            close()
        }
    }

    private func close() {
        Hotkeys.undo = nil
        removeMonitors()
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.2; panel.animator().alphaValue = 0 }) {
            Task { @MainActor in if panel.alphaValue == 0 { panel.orderOut(nil) } }
        }
    }

    private func makePanel() -> KeyPanel {
        let panel = KeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = NSHostingView(rootView: PopupView(model: model) { [weak self] in self?.run($0) })
        host.sizingOptions = [.intrinsicContentSize]
        panel.contentView = host
        self.panel = panel
        return panel
    }

    /// Below the selection, left-aligned with it; above it when there is no room below. Falls back to the mouse pointer.
    private func frame(near rect: CGRect?, size: CGSize) -> CGRect {
        let m = Self.margin, gap = Self.gap
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let anchor: CGRect
        if let rect {
            anchor = CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
        } else {
            let mouse = NSEvent.mouseLocation
            anchor = CGRect(x: mouse.x, y: mouse.y - 16, width: 0, height: 32)
        }
        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: anchor.minX, y: anchor.midY)) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(origin: anchor.origin, size: size)
        var y = anchor.minY - gap + m - size.height
        model.above = y < visible.minY
        if model.above { y = anchor.maxY + gap - m }
        let x = min(max(anchor.minX - m, visible.minX), visible.maxX - size.width)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    // MARK: Input

    private func installMonitors() {
        removeMonitors()
        if let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            (self?.handle(event) ?? false) ? nil : event
        }) { monitors.append(keys) }
        if let clicks = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            Task { @MainActor in if self?.model.phase == .menu { self?.close() } }
        }) { monitors.append(clicks) }
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    /// The field keeps first responder throughout; a highlighted button is model state only, so typing always lands in the field.
    private func handle(_ event: NSEvent) -> Bool {
        let key = Int(event.keyCode)
        if key == kVK_Escape { cancel(); return true }
        guard model.phase == .menu, !event.modifierFlags.contains(.command) else { return false }
        let count = model.actions.count
        let isReturn = key == kVK_Return || key == kVK_ANSI_KeypadEnter
        guard let selected = model.selected else {
            let empty = model.instruction.isEmpty
            switch key {
            case _ where isReturn: runInstruction()
            case kVK_RightArrow where empty && count > 0, kVK_Tab where count > 0: model.selected = 0
            case kVK_LeftArrow where empty && count > 0: model.selected = count - 1
            default: return false
            }
            return true
        }
        switch key {
        case kVK_LeftArrow: model.selected = selected == 0 ? nil : selected - 1
        case kVK_RightArrow, kVK_Tab: model.selected = selected == count - 1 ? nil : selected + 1
        case _ where isReturn, kVK_Space: run(selected)
        default:
            model.selected = nil
            return false
        }
        return true
    }
}
