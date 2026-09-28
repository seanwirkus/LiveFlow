import AppKit

/// Push-to-talk on the Fn (🌐) key: press starts dictation, release stops.
/// Uses NSEvent flagsChanged monitors, which require Accessibility permission.
final class FnKeyMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var fnDown = false

    private static let fnKeyCode: UInt16 = 63  // kVK_Function

    init(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) {
        let handle: (NSEvent) -> Void = { [weak self] event in
            guard let self, event.keyCode == FnKeyMonitor.fnKeyCode else { return }
            let down = event.modifierFlags.contains(.function)
            if down && !fnDown {
                fnDown = true
                onPress()
            } else if !down && fnDown {
                fnDown = false
                onRelease()
            }
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handle)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            handle(event)
            return event
        }
    }

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }
}
