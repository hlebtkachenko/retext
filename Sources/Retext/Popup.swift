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
        /// The result with its changes marked, before it replaces the selection ("Preview before replacing").
        case preview([TextDiff.Segment])
    }

    @Published var phase = Phase.menu
    @Published var actions: [CustomAction] = []
    /// nil = the instruction field; otherwise the highlighted action button.
    @Published var selected: Int?
    @Published var instruction = ""
    /// This run's level: the default level each time the bar opens; Up/Down change it.
    @Published var level = Level.medium
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
                case .preview(let segments): preview(segments)
                }
            }
            .glassEffect(.regular, in: isPreview ? AnyShape(RoundedRectangle(cornerRadius: 18)) : AnyShape(Capsule()))
            .glassEffectID("pill", in: glass)
        }
        .font(.body)
        .padding(PopupController.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: model.above ? .bottomLeading : .topLeading)
        .animation(.smooth(duration: 0.25), value: model.phase)
    }

    private var isPreview: Bool {
        if case .preview = model.phase { true } else { false }
    }

    /// The result with added words highlighted and removed ones struck through; scrolls past `maxHeight`.
    private func preview(_ segments: [TextDiff.Segment]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                Text(Self.marked(segments))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 260)
            .accessibilityLabel("Result: \(segments.filter { $0.kind != .deleted }.map(\.text).joined())")
            HStack(spacing: 14) {
                Text("↩ Replace")
                Text("esc Discard")
                Text("⌘C Copy")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 440)
    }

    static func marked(_ segments: [TextDiff.Segment]) -> AttributedString {
        segments.reduce(into: AttributedString()) { out, segment in
            var part = AttributedString(segment.text)
            switch segment.kind {
            case .equal: break
            case .inserted:
                part.backgroundColor = Color.green.opacity(0.28)
            case .deleted:
                part.strikethroughStyle = .single
                part.foregroundColor = Color.red.opacity(0.8)
            }
            out += part
        }
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
            levelChip
        }
        .padding(4)
    }

    /// The run's level; Up/Down step it, a click cycles it. Sized for the widest title so the capsule never clips.
    private var levelChip: some View {
        Button { model.level = model.level.next } label: {
            HStack(spacing: 2) {
                ZStack(alignment: .trailing) {
                    ForEach(Level.allCases, id: \.self) { Text($0.title).opacity($0 == model.level ? 1 : 0) }
                }
                Image(systemName: "chevron.up.chevron.down").imageScale(.small)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help("Level: ↑/↓ to change")
        .accessibilityLabel("Level \(model.level.title)")
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
    private var panel: KeyPanel?
    private var selection: Selection?
    private var work: Task<Void, Never>?
    /// Identifies the run that owns `work`.
    private var runID = 0
    private var hideTask: Task<Void, Never>?
    private var monitors: [Any] = []
    private var anchor: CGRect?
    /// The previewed result and the selection it would replace; nil once replaced, copied or discarded.
    private var pending: (text: String, selection: Selection)?
    /// Discards the preview when another app comes to the front.
    private var activation: NSObjectProtocol?

    /// ⌥Space opens the menu (or closes it); ⌥1…⌥9 pass an action index and run it straight away.
    func trigger(_ action: Int? = nil) {
        // Any Retext shortcut while a preview shows discards it, like Esc.
        if pending != nil { return close() }
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
            if let action, action >= model.actions.count { return }
            model.selected = nil
            model.instruction = ""
            model.level = AppState.shared.settings.defaultLevel
            model.phase = action.map { _ in .working("Working…") } ?? .menu
            show(near: selection.rect)
            if let action { run(action) }
        }
    }

    func demo(_ state: String) {
        model.actions = AppState.shared.settings.actions
        model.level = CommandLine.arguments.last.flatMap(Level.init(rawValue:)) ?? AppState.shared.settings.defaultLevel
        model.phase = switch state {
        case "working": .working("Translating to Czech…")
        case "done": .done
        case "error": .message(ClaudeFailure.other("").message(for: AppState.shared.settings.provider), isError: true)
        case "empty": .message("Select text first", isError: false)
        case "nochange": .message("No changes needed", isError: false, symbol: "checkmark.circle")
        case "preview": .preview(TextDiff.words(old: Self.demoOriginal(long: CommandLine.arguments.last == "long"),
                                                new: Self.demoResult(long: CommandLine.arguments.last == "long")))
        default: .menu
        }
        let f = (NSScreen.main ?? NSScreen.screens.first)?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        show(near: CGRect(x: f.midX - 200, y: f.height / 2 - 20, width: 400, height: 18))
        if let panel {  // screencapture -R rectangle (top-left origin) for screenshots
            let r = panel.frame
            print("capture \(Int(r.minX)),\(Int(f.maxY - r.maxY)),\(Int(r.width)),\(Int(r.height))")
            print("window \(panel.windowNumber)")  // for screencapture -l
            fflush(stdout)
        }
    }

    private static func demoOriginal(long: Bool) -> String {
        let text = "Hi Anna, thank you for you're message. I will sent the documents tomorow morning, and we can discuss about it on Friday."
        return long ? Array(repeating: text, count: 12).joined(separator: "\n\n") : text
    }

    private static func demoResult(long: Bool) -> String {
        let text = "Hi Anna, thank you for your message. I will send the documents tomorrow morning, and we can discuss it on Friday."
        return long ? Array(repeating: text, count: 12).joined(separator: "\n\n") : text
    }

    // MARK: Flow

    private func run(_ index: Int) {
        guard let selection, work == nil, model.actions.indices.contains(index) else { return }
        let action = model.actions[index]
        let settings = AppState.shared.settings
        model.selected = index
        execute(Engine.job(for: action, level: model.level, text: selection.text, settings: settings,
                           bundleID: selection.app.bundleIdentifier),
                progress: progress(for: action))
    }

    private func runInstruction() {
        let instruction = model.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let selection, !instruction.isEmpty else { return }
        execute(Engine.job(instruction: instruction, level: model.level, settings: AppState.shared.settings,
                           bundleID: selection.app.bundleIdentifier),
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
        model.phase = .working(model.level == .medium ? progress : "\(progress) · \(model.level.title)")
        fit()
        runID &+= 1
        let id = runID
        let timeout = model.level.timeout
        work = Task {
            // After Esc and a fast re-trigger, `work` already belongs to the next run.
            defer { if runID == id { work = nil } }
            do {
                let result = try await result(of: job, timeout: timeout, for: selection)
                // A cache hit returns without a cancellation check; after Esc nothing may show, copy or paste.
                try Task.checkCancellation()
                if Engine.isUnchanged(input: selection.text, output: result) {
                    return flash(.message("No changes needed", isError: false, symbol: "checkmark.circle"), for: 1.5)
                }
                let final = keepOuterWhitespace(of: selection.text, around: result)
                if !selection.editable { return copy(final, note: "Copied to clipboard") }
                if selection.hasAttachment { return copy(final, note: "Selection has an image, copied instead") }
                if !SelectionIO.stillSelected(selection) { return copy(final, note: "Selection changed. Copied.") }
                if AppState.shared.settings.previewBeforeReplace { return preview(final, for: selection) }
                await replace(selection, with: final)
            } catch {
                guard !Task.isCancelled, model.phase != .menu, panel?.isVisible == true else { return }
                let failure = error as? ClaudeFailure ?? .other("")
                if failure == .notFound || failure == .notLoggedIn { AppState.shared.checkProvider() }
                flash(.message(failure.message(for: job.provider), isError: true), for: failure == .other("") ? 3 : 5)
            }
        }
    }

    private func replace(_ selection: Selection, with text: String) async {
        panel?.orderOut(nil)
        await SelectionIO.replace(in: selection.app, with: text, attributes: selection.attributes)
        flash(.done, for: 1.2)
    }

    /// Shows the result with its changes marked and waits: Return replaces, Esc discards, ⌘C copies. No timer closes it.
    /// Shown only while the selection's app is still in front; otherwise the result is copied, so the preview never
    /// takes the keyboard from another app. Switching apps while it shows discards it.
    private func preview(_ text: String, for selection: Selection) {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == selection.app.processIdentifier else {
            return copy(text, note: "Selection changed. Copied.")
        }
        hideTask?.cancel()
        pending = (text, selection)
        model.phase = .preview(TextDiff.words(old: selection.text, new: text))
        fit()
        // Key again, in case a click elsewhere took the keyboard while the provider worked.
        panel?.makeKeyAndOrderFront(nil)
        // One observer is enough: it acts only while a preview is pending, and close() removes it.
        if activation == nil { activation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.pending != nil { self?.close() } }
        } }
    }

    /// Return in the preview: the same replace as without it, after checking the selection is still there.
    private func confirmPreview() {
        guard let pending, work == nil else { return }
        self.pending = nil
        if !SelectionIO.stillSelected(pending.selection) { return copy(pending.text, note: "Selection changed. Copied.") }
        runID &+= 1
        let id = runID
        work = Task {
            defer { if runID == id { work = nil } }
            // Wait (up to 1 s) for Return to come up while the panel still takes the keys, so a held Return
            // doesn't repeat into the source app after the paste re-activates it.
            var waited = 0
            while Self.returnIsDown, waited < 50 { try? await Task.sleep(for: .milliseconds(20)); waited += 1 }
            guard !Task.isCancelled else { return }
            await replace(pending.selection, with: pending.text)
        }
    }

    private static var returnIsDown: Bool {
        [kVK_Return, kVK_ANSI_KeypadEnter].contains { CGEventSource.keyState(.combinedSessionState, key: CGKeyCode($0)) }
    }

    private func copyPreview() {
        guard let pending else { return }
        self.pending = nil
        copy(pending.text, note: "Copied to clipboard")
    }

    /// The cached result when provider, model, effort, prompt and text match an entry in the history; otherwise the answer after
    /// `Engine.checkLayout`, recorded. A rejected answer is never recorded, so it can't come back as a cache hit.
    /// With "Keep history" off, neither the cache nor the history is touched.
    private func result(of job: Job, timeout: Duration, for selection: Selection) async throws -> String {
        let state = AppState.shared
        let key = Engine.cacheKey(job, baseURL: state.settings.custom.baseURL, text: selection.text)
        let keep = state.settings.keepHistory
        if keep, let hit = state.history.lookup(key) {
            state.usage.recordHit()
            return hit.output
        }
        let output = try await ProviderRunner.run(job, text: selection.text, settings: state.settings, timeout: timeout)
        try Task.checkCancellation()
        state.usage.recordCall(model: job.model, output: output)
        guard let text = Engine.checkLayout(input: selection.text, output: output.text, kind: job.kind, styled: job.styled) else { throw ClaudeFailure.extraText }
        if keep { state.history.add(HistoryEntry(key: key, appName: selection.app.localizedName ?? "", title: job.title,
                                       input: selection.text, output: text, model: job.model,
                                       inputTokens: output.inputTokens, outputTokens: output.outputTokens, costUSD: output.costUSD)) }
        return text
    }

    /// For text that can't be edited in place: copy the result; while the bubble shows, ⌘Z brings the old clipboard back.
    private func copy(_ text: String, note: String) {
        let restore = SelectionIO.copyRestorable(text)
        Hotkeys.undo = nil
        if let restore {
            Hotkeys.undo = { [weak self] in
                restore()
                self?.flash(.message("Previous clipboard restored", isError: false, symbol: "arrow.uturn.backward"), for: 1.2)
            }
        }
        flash(.message(note, isError: false, hint: restore == nil ? nil : "⌘Z restores previous", symbol: "doc.on.clipboard"), for: 4)
    }

    private func cancel() {
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
        pending = nil
        if let activation { NSWorkspace.shared.notificationCenter.removeObserver(activation) }
        activation = nil
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
            // A click elsewhere closes the menu and discards a preview.
            Task { @MainActor in if self?.model.phase == .menu || self?.pending != nil { self?.close() } }
        }) { monitors.append(clicks) }
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    /// The field keeps first responder throughout; a highlighted button is model state only, so typing always lands in the field.
    /// Only the bar's own keys: a local monitor also sees keys meant for Settings or the welcome window.
    private func handle(_ event: NSEvent) -> Bool {
        guard event.window === panel else { return false }
        let key = Int(event.keyCode)
        if key == kVK_Escape { cancel(); return true }
        if case .preview = model.phase {
            // After Return, pending is nil but the panel keeps the keys until the replace: swallow repeats.
            guard pending != nil else { return true }
            if key == kVK_Return || key == kVK_ANSI_KeypadEnter { confirmPreview() }
            // The key code works on any layout (Cyrillic); the character keeps ⌘C where C sits elsewhere (Dvorak).
            if event.modifierFlags.contains(.command), key == kVK_ANSI_C || event.charactersIgnoringModifiers?.lowercased() == "c" {
                copyPreview()
            }
            return true
        }
        guard model.phase == .menu, !event.modifierFlags.contains(.command) else { return false }
        let count = model.actions.count
        let isReturn = key == kVK_Return || key == kVK_ANSI_KeypadEnter
        // Up/Down step the level wherever the highlight is; swallowing them keeps the field's cursor still.
        if key == kVK_UpArrow || key == kVK_DownArrow {
            model.level = model.level.stepped(by: key == kVK_UpArrow ? 1 : -1)
            return true
        }
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
