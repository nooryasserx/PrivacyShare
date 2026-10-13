import AppKit
import CoreGraphics

struct TargetWindow {
    let id: CGWindowID
    let pid: pid_t
    let frame: CGRect      // global, top-left origin (CoreGraphics coordinates)
    let layer: Int
}

/// Finds every on-screen window that should be hidden from screen sharing.
final class WindowScanner {
    private static let notificationBundles: Set<String> = [
        "com.apple.notificationcenterui",
        "com.apple.UserNotificationCenter",
    ]

    private let ownPID = getpid()
    private var bundleCache: [pid_t: String] = [:]

    func scan(rules: RulesSnapshot) -> [TargetWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]]
        else { return [] }

        if bundleCache.count > 500 { bundleCache.removeAll() }
        let screenWidth = NSScreen.main?.frame.width ?? 1440
        var result: [TargetWindow] = []

        for info in list {
            guard let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  pid != ownPID,
                  let number = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  rect.width >= 40, rect.height >= 30
            else { continue }

            let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            guard alpha > 0.01, layer >= 0 else { continue }

            let title = info[kCGWindowName as String] as? String ?? ""
            let bundle = bundleID(for: pid)

            if isSensitive(bundle: bundle, title: title, layer: layer, rect: rect,
                           screenWidth: screenWidth, rules: rules) {
                result.append(TargetWindow(id: number, pid: pid, frame: rect, layer: layer))
            }
        }
        return result
    }

    private func isSensitive(bundle: String, title: String, layer: Int, rect: CGRect,
                             screenWidth: CGFloat, rules: RulesSnapshot) -> Bool {
        if rules.bundleIDs.contains(bundle) { return true }

        if rules.blurNotifications, Self.notificationBundles.contains(bundle),
           layer > 0, rect.width < screenWidth * 0.9 {
            return true
        }

        if !title.isEmpty {
            for keyword in rules.keywords where !keyword.isEmpty {
                if title.localizedCaseInsensitiveContains(keyword) { return true }
            }
        }
        return false
    }

    private func bundleID(for pid: pid_t) -> String {
        if let cached = bundleCache[pid] { return cached }
        let id = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
        bundleCache[pid] = id
        return id
    }
}
