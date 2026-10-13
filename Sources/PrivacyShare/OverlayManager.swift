import AppKit
import ScreenCaptureKit

/// Watches the screen ~30×/sec and keeps a WindowMirror on top of every private window.
final class OverlayManager: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var protectedCount = 0
    @Published private(set) var statusMessage = "الحماية متوقفة"

    private var timer: Timer?
    private let scanner = WindowScanner()
    private var mirrors: [CGWindowID: WindowMirror] = [:]

    @MainActor
    func toggle() async {
        if isEnabled { disable() } else { await enable() }
    }

    @MainActor
    func enable() async {
        guard !isEnabled else { return }

        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
            statusMessage = "اعطِ التطبيق صلاحية Screen Recording من System Settings ← Privacy & Security، وبعدين سكّره وافتحه من جديد."
            return
        }
        // Make sure ScreenCaptureKit is actually usable before we start.
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            statusMessage = "ما قدرت أصوّر الشاشة: \(error.localizedDescription)"
            return
        }

        isEnabled = true
        statusMessage = "الحماية شغّالة – شارك شاشتك عادي"
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    func disable() {
        timer?.invalidate()
        timer = nil
        mirrors.values.forEach { $0.stop() }
        mirrors.removeAll()
        isEnabled = false
        protectedCount = 0
        statusMessage = "الحماية متوقفة"
    }

    private func tick() {
        let rules = PrivacySettings.shared.snapshot()
        let targets = scanner.scan(rules: rules)
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        var seen = Set<CGWindowID>()
        for target in targets {
            seen.insert(target.id)
            let active = target.pid == frontPID
            if let mirror = mirrors[target.id] {
                mirror.update(target: target, appActive: active)
            } else {
                let mirror = WindowMirror(target: target)
                mirrors[target.id] = mirror
                mirror.update(target: target, appActive: active)   // cover appears immediately
                startCapture(for: mirror, windowID: target.id)
            }
        }

        let gone = mirrors.keys.filter { !seen.contains($0) }
        for id in gone {
            mirrors[id]?.stop()
            mirrors[id] = nil
        }

        if protectedCount != mirrors.count { protectedCount = mirrors.count }
    }

    private func startCapture(for mirror: WindowMirror, windowID: CGWindowID) {
        Task { @MainActor in
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
                  let scWindow = content.windows.first(where: { $0.windowID == windowID })
            else { return }
            await mirror.start(scWindow: scWindow)
        }
    }
}
