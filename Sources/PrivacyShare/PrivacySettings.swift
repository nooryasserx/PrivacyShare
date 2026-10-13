import Foundation

enum ObscureStyle: String, CaseIterable, Identifiable {
    case blur, pixelate, solid
    var id: String { rawValue }
    var title: String {
        switch self {
        case .blur: return "تغبيش"
        case .pixelate: return "بكسلة"
        case .solid: return "حجب كامل"
        }
    }
}

/// Thread-safe copy of the rules, read by the capture queue on every frame.
struct RulesSnapshot {
    var bundleIDs: Set<String>
    var keywords: [String]
    var blurNotifications: Bool
    var intensity: Double
    var style: ObscureStyle
}

final class PrivacySettings: ObservableObject {
    static let shared = PrivacySettings()

    static let defaultBundleIDs: [String] = [
        "net.whatsapp.WhatsApp",
        "desktop.WhatsApp",
        "ru.keepcoder.Telegram",
        "org.telegram.desktop",
        "com.apple.MobileSMS",
        "com.apple.mail",
        "org.whispersystems.signal-desktop",
    ]
    static let defaultKeywords = ["WhatsApp", "Telegram", "Gmail", "Messenger", "Instagram"]

    @Published var blurredBundleIDs: Set<String> { didSet { persist() } }
    @Published var titleKeywords: [String] { didSet { persist() } }
    @Published var blurNotifications: Bool { didSet { persist() } }
    @Published var intensity: Double { didSet { persist() } }
    @Published var style: ObscureStyle { didSet { persist() } }

    private let lock = NSLock()
    private var current: RulesSnapshot

    private init() {
        let d = UserDefaults.standard
        let ids = Set(d.stringArray(forKey: "bundleIDs") ?? Self.defaultBundleIDs)
        let kws = d.stringArray(forKey: "keywords") ?? Self.defaultKeywords
        let notif = d.object(forKey: "notifications") as? Bool ?? true
        let inten = d.object(forKey: "intensity") as? Double ?? 6
        let st = ObscureStyle(rawValue: d.string(forKey: "style") ?? "") ?? .blur

        blurredBundleIDs = ids
        titleKeywords = kws
        blurNotifications = notif
        intensity = inten
        style = st
        current = RulesSnapshot(bundleIDs: ids, keywords: kws, blurNotifications: notif,
                                intensity: inten, style: st)
    }

    func snapshot() -> RulesSnapshot {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    private func persist() {
        let snap = RulesSnapshot(bundleIDs: blurredBundleIDs, keywords: titleKeywords,
                                 blurNotifications: blurNotifications, intensity: intensity, style: style)
        lock.lock(); current = snap; lock.unlock()

        let d = UserDefaults.standard
        d.set(Array(snap.bundleIDs), forKey: "bundleIDs")
        d.set(snap.keywords, forKey: "keywords")
        d.set(snap.blurNotifications, forKey: "notifications")
        d.set(snap.intensity, forKey: "intensity")
        d.set(snap.style.rawValue, forKey: "style")
    }
}
