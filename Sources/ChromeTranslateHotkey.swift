import Cocoa
import Carbon
import ApplicationServices
import CoreGraphics

private let hotKeySignature: OSType = 0x52595452 // "RYTR"
private let hotKeyIDValue: UInt32 = 1
private let chromeBundleID = "com.google.Chrome"
private let exactTranslateTitle = "翻译成中文（简体）"

func axString(_ element: AXUIElement, _ attribute: String) -> String {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
          let value else { return "" }
    return value as? String ?? ""
}

func axElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
          let value else { return nil }
    return (value as! AXUIElement)
}

func axPoint(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
          let value,
          CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    let axv = unsafeBitCast(value, to: AXValue.self)
    var p = CGPoint.zero
    guard AXValueGetValue(axv, .cgPoint, &p) else { return nil }
    return p
}

func axSize(_ element: AXUIElement, _ attribute: String) -> CGSize? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
          let value,
          CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    let axv = unsafeBitCast(value, to: AXValue.self)
    var s = CGSize.zero
    guard AXValueGetValue(axv, .cgSize, &s) else { return nil }
    return s
}

func frontChromeWindowRect() -> CGRect? {
    guard let front = NSWorkspace.shared.frontmostApplication,
          front.bundleIdentifier == chromeBundleID else { return nil }

    let app = AXUIElementCreateApplication(front.processIdentifier)
    guard let win = axElement(app, kAXFocusedWindowAttribute),
          let p = axPoint(win, kAXPositionAttribute),
          let s = axSize(win, kAXSizeAttribute),
          s.width > 300, s.height > 300 else { return nil }
    return CGRect(origin: p, size: s)
}

func postRightClick(at point: CGPoint) {
    let src = CGEventSource(stateID: .hidSystemState)
    CGEvent(mouseEventSource: src, mouseType: .rightMouseDown,
            mouseCursorPosition: point, mouseButton: .right)?.post(tap: .cghidEventTap)
    usleep(55_000)
    CGEvent(mouseEventSource: src, mouseType: .rightMouseUp,
            mouseCursorPosition: point, mouseButton: .right)?.post(tap: .cghidEventTap)
}

func postEscape() {
    let src = CGEventSource(stateID: .hidSystemState)
    let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Escape), keyDown: true)
    let up = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Escape), keyDown: false)
    down?.post(tap: .cghidEventTap)
    usleep(20_000)
    up?.post(tap: .cghidEventTap)
}

func moveMouse(to point: CGPoint) {
    let src = CGEventSource(stateID: .hidSystemState)
    CGEvent(mouseEventSource: src, mouseType: .mouseMoved,
            mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
}

func isDesiredTranslateTitle(_ title: String) -> Bool {
    if title == exactTranslateTitle { return true }
    return title.contains("翻译")
        && title.contains("中文")
        && title.contains("简体")
        && !title.contains("所选内容")
}

func findAndPressTranslate(near point: CGPoint) -> String? {
    let system = AXUIElementCreateSystemWide()

    let minX = max(0, Int(point.x) - 620)
    let maxX = Int(point.x) + 120
    let minY = max(0, Int(point.y) - 650)
    let maxY = Int(point.y) + 120

    // Context menus are compact. A 12 px grid is enough to hit every row
    // while keeping invocation fast.
    for y in stride(from: minY, through: maxY, by: 12) {
        for x in stride(from: minX, through: maxX, by: 12) {
            var element: AXUIElement?
            guard AXUIElementCopyElementAtPosition(system, Float(x), Float(y), &element) == .success,
                  let element else { continue }

            if axString(element, kAXRoleAttribute) != (kAXMenuItemRole as String) { continue }
            let title = axString(element, kAXTitleAttribute)
            if isDesiredTranslateTitle(title) {
                if AXUIElementPerformAction(element, kAXPressAction as CFString) == .success {
                    return title
                }
            }
        }
    }
    return nil
}

func triggerChromeBuiltInTranslate() -> (Bool, String) {
    guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == chromeBundleID else {
        return (false, "chrome_not_frontmost")
    }
    guard AXIsProcessTrusted() else {
        return (false, "accessibility_not_authorized")
    }
    guard let rect = frontChromeWindowRect() else {
        return (false, "chrome_window_not_found")
    }

    let originalMouse = CGEvent(source: nil)?.location

    // Try several low-collision points in the web-content area. If a point
    // happens to be on selected text/image/link, close that menu and retry.
    let candidates = [
        CGPoint(x: rect.maxX - 150, y: rect.maxY - 150),
        CGPoint(x: rect.maxX - 150, y: rect.minY + max(220, rect.height * 0.34)),
        CGPoint(x: rect.minX + 150, y: rect.maxY - 150),
        CGPoint(x: rect.minX + rect.width * 0.76, y: rect.minY + rect.height * 0.66),
        CGPoint(x: rect.minX + rect.width * 0.24, y: rect.minY + rect.height * 0.66)
    ]

    for point in candidates {
        postRightClick(at: point)
        usleep(260_000)

        if let title = findAndPressTranslate(near: point) {
            usleep(80_000)
            if let originalMouse { moveMouse(to: originalMouse) }
            return (true, "pressed:\(title)")
        }

        postEscape()
        usleep(100_000)
    }

    if let originalMouse { moveMouse(to: originalMouse) }
    return (false, "translate_menu_item_not_found")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/ChromeTranslateHotkey.log")

    func log(_ message: String) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let line = "[\(f.string(from: Date()))] \(message)\n"
        let data = Data(line.utf8)
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        if let h = try? FileHandle(forWritingTo: logURL) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: data)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handler: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                let result = triggerChromeBuiltInTranslate()
                delegate.log("hotkey_triggered handled=\(result.0 ? 1 : 0) reason=\(result.1)")
            }
            return noErr
        }

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: hotKeyIDValue)
        let modifiers = UInt32(controlKey | optionKey)
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_T),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        log("started pid=\(ProcessInfo.processInfo.processIdentifier) handler_status=\(installStatus) hotkey_register_status=\(registerStatus) ax_trusted=\(AXIsProcessTrusted() ? 1 : 0)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
        log("terminated")
    }
}

let args = CommandLine.arguments

if args.count >= 2 && args[1] == "--ax-status" {
    print(AXIsProcessTrusted() ? "trusted" : "not-trusted")
    exit(AXIsProcessTrusted() ? 0 : 4)
}

if args.count >= 2 && args[1] == "--builtin-test" {
    let result = triggerChromeBuiltInTranslate()
    print(result.0 ? "handled \(result.1)" : "not-handled \(result.1)")
    exit(result.0 ? 0 : 3)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
