import AppKit
import Carbon.HIToolbox

struct Selection {
    let app: NSRunningApplication
    let text: String
    /// Font, size, colour and paragraph style of the selection's first character, when the app copies rich text.
    let attributes: [NSAttributedString.Key: Any]?
    /// False for read-only text (web pages, PDFs, received mail): the result is copied, not pasted.
    let editable: Bool
    /// Selection bounds in AX coordinates (origin at top-left of the primary screen), when the app reports them.
    let rect: CGRect?
}

/// Reads and replaces the selected text in the frontmost app through Accessibility, with a clipboard fallback.
enum SelectionIO {
    static func read() async -> Selection? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        enableElectronAccessibility(app)
        let element = focusedElement(of: app)
        let copied = await copyViaClipboard()
        var text = copied?.text
        if text?.isEmpty ?? true { text = element.flatMap(selectedText) }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return Selection(app: app, text: text, attributes: copied?.attributes, editable: element.map(isEditable) ?? true,
                         rect: element.flatMap(bounds))
    }

    /// Whether the source app still has the same text selected. Unknown counts as unchanged.
    /// Whitespace is ignored because AX and the clipboard can differ in line endings.
    /// Asks the source app, not the system-wide focus, which can be Retext's own instruction field.
    static func stillSelected(_ selection: Selection) -> Bool {
        let text = selection.text
        guard let now = focusedElement(of: selection.app).flatMap(selectedText), !now.isEmpty else { return true }
        let squash = { (s: String) in s.filter { !$0.isWhitespace && !$0.isNewline } }
        return squash(now) == squash(text)
    }

    /// Pastes `text` over the selection. With `attributes` it goes in as rich text in the original style,
    /// so apps like Mail keep the font instead of falling back to their default.
    static func replace(in app: NSRunningApplication, with text: String, attributes: [NSAttributedString.Key: Any]?) async {
        let saved = snapshot()
        let pb = NSPasteboard.general
        pb.clearContents()
        if let attributes {
            let rich = NSAttributedString(string: text, attributes: attributes)
            if let rtf = rich.rtf(from: NSRange(location: 0, length: rich.length), documentAttributes: [:]) {
                pb.setData(rtf, forType: .rtf)
            }
        }
        pb.setString(text, forType: .string)
        pb.setData(Data(), forType: transient)
        app.activate()
        try? await Task.sleep(for: .milliseconds(150))
        press(kVK_ANSI_V)
        // Note: fixed wait before restoring the clipboard; raise it if a slow app pastes the old clipboard.
        try? await Task.sleep(for: .milliseconds(700))
        restore(saved)
    }

    /// Copies `text` and returns a closure that puts the previous clipboard back, or nil when it was empty.
    static func copyRestorable(_ text: String) -> (() -> Void)? {
        let saved = snapshot()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return saved.allSatisfy(\.isEmpty) ? nil : { restore(saved) }
    }

    // MARK: Accessibility

    /// The app's focused element. The timeout applies to the app and to the element, so a hung app can't
    /// stall the main thread (stillSelected, isEditable and bounds all query this element).
    static func focusedElement(of app: NSRunningApplication, timeout: Float = 0.2) -> AXUIElement? {
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, timeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = value as! AXUIElement
        AXUIElementSetMessagingTimeout(element, timeout)
        return element
    }

    private static func isEditable(_ element: AXUIElement) -> Bool {
        var role: CFTypeRef?, ancestor: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        if let role = role as? String, [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField"].contains(role) { return true }
        var settable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success, settable.boolValue { return true }
        return AXUIElementCopyAttributeValue(element, "AXEditableAncestor" as CFString, &ancestor) == .success && ancestor != nil
    }

    static func selectedText(_ element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    /// Where to anchor the popup: the selection's bounds when they lie inside the text field,
    /// else the text field itself when it is small enough (Electron and web apps often report bogus bounds).
    private static func bounds(_ element: AXUIElement) -> CGRect? {
        let field = frame(element)
        if let rect = selectionBounds(element), field.map({ $0.insetBy(dx: -4, dy: -4).contains(rect) }) ?? true {
            return rect
        }
        if let field, field.height <= 240 { return field }
        return nil
    }

    private static func selectionBounds(_ element: AXUIElement) -> CGRect? {
        var range: CFTypeRef?, value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success, let range,
              AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, range, &value) == .success,
              let value else { return nil }
        return cgRect(value)
    }

    private static func frame(_ element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size, CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin), AXValueGetValue(size as! AXValue, .cgSize, &extent),
              extent.width > 1, extent.height > 1 else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    private static func cgRect(_ value: CFTypeRef) -> CGRect? {
        var rect = CGRect.zero
        guard CFGetTypeID(value) == AXValueGetTypeID(), AXValueGetValue(value as! AXValue, .cgRect, &rect),
              rect.width > 1, rect.height > 1 else { return nil }
        return rect
    }

    /// Electron apps (Claude, Slack, VS Code) build their accessibility tree only when asked; unsupported apps ignore it.
    static func enableElectronAccessibility(_ app: NSRunningApplication) {
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.1)  // also runs inside the event tap, which must not stall
        AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    // MARK: Clipboard

    private typealias Snapshot = [[NSPasteboard.PasteboardType: Data]]
    /// nspasteboard.org marker: clipboard managers skip transient items. A concealed marker (passwords) is just
    /// another type in a snapshot, so it is restored with the rest.
    private static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    private static func snapshot() -> Snapshot {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
    }

    private static func restore(_ saved: Snapshot) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(saved.map { types in
            let item = NSPasteboardItem()
            types.forEach { item.setData($1, forType: $0) }
            // The old clipboard coming back is not a new copy. A concealed marker is kept, so a restored password stays hidden.
            item.setData(Data(), forType: transient)
            return item
        })
    }

    private static func copyViaClipboard() async -> (text: String?, attributes: [NSAttributedString.Key: Any]?)? {
        let saved = snapshot()
        let before = NSPasteboard.general.changeCount
        press(kVK_ANSI_C)
        for _ in 0..<10 where NSPasteboard.general.changeCount == before {
            try? await Task.sleep(for: .milliseconds(40))
        }
        guard NSPasteboard.general.changeCount != before else { return nil }
        let pb = NSPasteboard.general
        var attributes: [NSAttributedString.Key: Any]?
        if let data = pb.data(forType: .rtf), let rich = NSAttributedString(rtf: data, documentAttributes: nil), rich.length > 0 {
            attributes = rich.attributes(at: 0, effectiveRange: nil)
        } else if let data = pb.data(forType: .rtfd), let rich = NSAttributedString(rtfd: data, documentAttributes: nil), rich.length > 0 {
            attributes = rich.attributes(at: 0, effectiveRange: nil)
        }
        let text = pb.string(forType: .string)
        restore(saved)
        return (text, attributes)
    }

    private static func press(_ key: Int) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}
