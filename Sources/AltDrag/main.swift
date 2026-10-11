import Cocoa
import ApplicationServices

// MARK: - Drag State

private var leftDragging = false
private var rightDragPending = false
private var rightDragging = false
private var dragStartMouse: CGPoint = .zero
private var dragStartOrigin: CGPoint = .zero
private var draggedWindow: AXUIElement?
private let dragThreshold: CGFloat = 5

// MARK: - AX Attribute Constants

private let kAXWindows = "AXWindows" as CFString
private let kAXPosition = "AXPosition" as CFString
private let kAXSize = "AXSize" as CFString

// MARK: - Window Finding

/// Find the topmost standard window at the given screen coordinate.
private func windowAtPoint(_ point: CGPoint) -> AXUIElement? {
    guard let list = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
    ) as? [[String: Any]] else { return nil }

    // CGWindowList returns windows ordered front-to-back
    for info in list {
        // Skip non-standard window layers (menu bar, dock, tooltips, etc.)
        if let layer = (info["kCGWindowLayer"] as? NSNumber)?.intValue, layer != 0 { continue }
        // Skip transparent windows
        if let alpha = (info["kCGWindowAlpha"] as? NSNumber)?.doubleValue, alpha < 0.1 { continue }

        guard let b = info["kCGWindowBounds"] as? [String: Any],
              let x = (b["X"] as? NSNumber)?.doubleValue,
              let y = (b["Y"] as? NSNumber)?.doubleValue,
              let w = (b["Width"] as? NSNumber)?.doubleValue,
              let h = (b["Height"] as? NSNumber)?.doubleValue else { continue }

        guard CGRect(x: x, y: y, width: w, height: h).contains(point) else { continue }

        // Get the owner PID and find the matching AXUIElement window
        guard let pid = (info["kCGWindowOwnerPID"] as? NSNumber)?.int32Value else { continue }
        let app = AXUIElementCreateApplication(pid)

        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindows, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else { continue }

        for win in windows {
            var posRef: CFTypeRef?
            AXUIElementCopyAttributeValue(win, kAXPosition, &posRef)
            guard let pv = posRef else { continue }
            var origin = CGPoint()
            AXValueGetValue(pv as! AXValue, .cgPoint, &origin)

            var sizeRef: CFTypeRef?
            AXUIElementCopyAttributeValue(win, kAXSize, &sizeRef)
            guard let sv = sizeRef else { continue }
            var size = CGSize()
            AXValueGetValue(sv as! AXValue, .cgSize, &size)

            if CGRect(origin: origin, size: size).contains(point) {
                return win
            }
        }
    }
    return nil
}

// MARK: - Window Helpers

private func moveWindow(_ win: AXUIElement, _ origin: CGPoint) {
    var pt = origin
    if let v = AXValueCreate(.cgPoint, &pt) {
        AXUIElementSetAttributeValue(win, kAXPosition, v)
    }
}

private func getOrigin(_ win: AXUIElement) -> CGPoint {
    var ref: CFTypeRef?
    AXUIElementCopyAttributeValue(win, kAXPosition, &ref)
    if let v = ref {
        var o = CGPoint()
        AXValueGetValue(v as! AXValue, .cgPoint, &o)
        return o
    }
    return .zero
}

private func startDrag(_ win: AXUIElement, _ mouse: CGPoint) {
    draggedWindow = win
    dragStartMouse = mouse
    dragStartOrigin = getOrigin(win)
}

// MARK: - Event Tap Callback

/// C-function-pointer callback — must NOT capture context.
/// All state is in module-level globals above.
private let callback: CGEventTapCallBack = { _, type, event, _ in
    let flags = event.flags
    let optionDown = flags.contains(.maskAlternate)
    let loc = event.location

    switch type {

    // ──── Left button: Option + left-drag → move ────

    case .leftMouseDown:
        if optionDown, let win = windowAtPoint(loc) {
            startDrag(win, loc)
            leftDragging = true
            return nil  // consume — underlying app never sees this click
        }

    case .leftMouseDragged:
        if leftDragging, let win = draggedWindow {
            moveWindow(win, CGPoint(
                x: dragStartOrigin.x + loc.x - dragStartMouse.x,
                y: dragStartOrigin.y + loc.y - dragStartMouse.y
            ))
            return nil
        }

    case .leftMouseUp:
        if leftDragging {
            leftDragging = false
            draggedWindow = nil
            return nil
        }

    // ──── Right button: right-drag → move (threshold-based) ────
    //
    // macOS context menus appear on mouse-UP, not mouse-DOWN.
    // Strategy: let mouse-down pass through. If the user drags more than
    // `dragThreshold` pixels before releasing, enter window-drag mode and
    // consume all subsequent events (including mouse-up → no context menu).
    // If the user releases without dragging, everything passes through and
    // the context menu appears normally.

    case .rightMouseDown:
        rightDragPending = true
        dragStartMouse = loc
        // pass through

    case .rightMouseDragged:
        if rightDragging, let win = draggedWindow {
            moveWindow(win, CGPoint(
                x: dragStartOrigin.x + loc.x - dragStartMouse.x,
                y: dragStartOrigin.y + loc.y - dragStartMouse.y
            ))
            return nil
        }
        if rightDragPending {
            let dx = loc.x - dragStartMouse.x
            let dy = loc.y - dragStartMouse.y
            if dx * dx + dy * dy > dragThreshold * dragThreshold {
                rightDragPending = false
                if let win = windowAtPoint(dragStartMouse) {
                    startDrag(win, dragStartMouse)
                    rightDragging = true
                    // immediately move to current cursor position
                    moveWindow(win, CGPoint(
                        x: dragStartOrigin.x + loc.x - dragStartMouse.x,
                        y: dragStartOrigin.y + loc.y - dragStartMouse.y
                    ))
                    return nil
                }
            }
        }
        // pass through while still pending

    case .rightMouseUp:
        if rightDragging {
            rightDragging = false
            draggedWindow = nil
            return nil  // consume → no context menu
        }
        if rightDragPending {
            rightDragPending = false
            // pass through → normal right-click, context menu appears
        }

    default:
        break
    }

    return Unmanaged.passUnretained(event)
}

// MARK: - AppDelegate (menu bar icon)

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // ── Accessibility permission check ──
        if !AXIsProcessTrustedWithOptions(nil) {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "需要辅助功能权限"
            alert.informativeText = "请在 系统设置 > 隐私与安全性 > 辅助功能 中授权 AltDrag，然后重新运行。"
            alert.addButton(withTitle: "打开设置")
            alert.addButton(withTitle: "退出")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                )
            }
            NSApp.terminate(nil)
            return
        }

        // ── Menu bar icon ──
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let btn = statusItem?.button {
            btn.title = "⌥"
        }
        let menu = NSMenu()
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 AltDrag",
                                action: #selector(NSApp.terminate),
                                keyEquivalent: "q"))
        statusItem?.menu = menu

        // ── Event tap ──
        let mask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue)    |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue)      |
            (1 << CGEventType.rightMouseDown.rawValue)   |
            (1 << CGEventType.rightMouseDragged.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: nil
        ) else {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "无法创建事件监听"
            alert.informativeText = "请确保已授予辅助功能权限，且没有其他程序占用事件监听。"
            alert.addButton(withTitle: "好")
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        print("AltDrag is running.")
        print("  Option + 左键拖动 → 移动窗口")
        print("  右键拖动         → 移动窗口（不干扰正常右键菜单）")
    }
}

// MARK: - Main

let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // no dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
