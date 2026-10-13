import AppKit
import SwiftUI

struct AppItem: Identifiable {
    let id: String      // bundle identifier
    let name: String
    let icon: NSImage?
}

struct ContentView: View {
    @EnvironmentObject private var manager: OverlayManager
    @EnvironmentObject private var settings: PrivacySettings

    @State private var apps: [AppItem] = []
    @State private var newKeyword = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statusBox
                appsBox
                keywordsBox
                styleBox
                helpBox
            }
            .padding(20)
        }
        .frame(width: 480, height: 720)
        .environment(\.layoutDirection, .rightToLeft)
        .onAppear(perform: reloadApps)
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            reloadApps()
        }
    }

    // MARK: Sections

    private var statusBox: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Circle()
                        .fill(manager.isEnabled ? Color.green : Color.gray)
                        .frame(width: 10, height: 10)
                        .padding(.top, 4)
                    Text(manager.statusMessage).font(.callout)
                    Spacer()
                }
                if manager.isEnabled {
                    Text("نوافذ محمية هلأ: \(manager.protectedCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Button(manager.isEnabled ? "إيقاف الحماية" : "تشغيل الحماية") {
                    Task { await manager.toggle() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        } label: {
            Label("الحالة", systemImage: "eye.slash")
        }
    }

    private var appsBox: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(apps) { app in
                    Toggle(isOn: binding(for: app.id)) {
                        HStack(spacing: 8) {
                            if let icon = app.icon {
                                Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                            }
                            Text(app.name)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
                Button("تحديث القائمة", action: reloadApps)
                    .buttonStyle(.link)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        } label: {
            Label("التطبيقات اللي بتتغبّش", systemImage: "app.badge")
        }
    }

    private var keywordsBox: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("أي نافذة (حتى تاب في المتصفح) عنوانها فيه وحدة من هاي الكلمات بتتغبّش.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ForEach(settings.titleKeywords, id: \.self) { keyword in
                    HStack {
                        Text(keyword)
                        Spacer()
                        Button {
                            settings.titleKeywords.removeAll { $0 == keyword }
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }

                HStack {
                    TextField("مثلاً: Gmail", text: $newKeyword)
                        .onSubmit(addKeyword)
                    Button("إضافة", action: addKeyword)
                }

                Divider()
                Toggle("غبّش الإشعارات المنبثقة", isOn: $settings.blurNotifications)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        } label: {
            Label("كلمات في عنوان النافذة", systemImage: "globe")
        }
    }

    private var styleBox: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Picker("الشكل", selection: $settings.style) {
                    ForEach(ObscureStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                if settings.style != .solid {
                    HStack {
                        Text("القوة")
                        Slider(value: $settings.intensity, in: 2...20)
                    }
                }
            }
            .padding(6)
        } label: {
            Label("شكل التغبيش", systemImage: "drop")
        }
    }

    private var helpBox: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Text("١. اختار التطبيقات والكلمات اللي بدك تغبّشها.")
                Text("٢. اضغط \"تشغيل الحماية\".")
                Text("٣. شارك شاشتك عادي (Entire Screen). انت بتشوف كل شي طبيعي، والطرف التاني بيشوف التطبيقات مغبّشة.")
                Text("للتجربة: خذ سكرين شوت (Cmd + Shift + 3)، لازم يطلع واتساب فيها مغبّش.")
                    .foregroundColor(.secondary)
                Text("فيك تسكّر هاي النافذة، والتطبيق بيضل شغّال من أيقونة العين فوق بشريط القوائم.")
                    .foregroundColor(.secondary)
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        } label: {
            Label("طريقة الاستخدام", systemImage: "questionmark.circle")
        }
    }

    // MARK: Helpers

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { settings.blurredBundleIDs.contains(id) },
            set: { on in
                if on { settings.blurredBundleIDs.insert(id) } else { settings.blurredBundleIDs.remove(id) }
            }
        )
    }

    private func addKeyword() {
        let k = newKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty, !settings.titleKeywords.contains(where: { $0.caseInsensitiveCompare(k) == .orderedSame })
        else { return }
        settings.titleKeywords.append(k)
        newKeyword = ""
    }

    private func reloadApps() {
        var seen = Set<String>()
        var items: [AppItem] = []

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier, !seen.contains(id) else { continue }
            seen.insert(id)
            items.append(AppItem(id: id, name: app.localizedName ?? id, icon: app.icon))
        }

        // Also show selected apps that are installed but not running right now.
        for id in settings.blurredBundleIDs where !seen.contains(id) {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { continue }
            seen.insert(id)
            let name = url.deletingPathExtension().lastPathComponent
            items.append(AppItem(id: id, name: name, icon: NSWorkspace.shared.icon(forFile: url.path)))
        }

        let selected = settings.blurredBundleIDs
        apps = items.sorted { a, b in
            let sa = selected.contains(a.id), sb = selected.contains(b.id)
            if sa != sb { return sa }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}
