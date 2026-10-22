import SwiftUI
import SysmonCore

/// 关于窗口：App 图标、名字、版本号、一句简介和 GitHub 地址。
/// 版本号从程序包的 Info.plist 读（由 scripts/bundle.sh 写入），直接 swift run 时显示 dev。
struct AboutView: View {
    @ObservedObject var preferences: Preferences
    static let repoURL = URL(string: "https://github.com/pokoblin/esp32-2432S024r-macos")!

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    var body: some View {
        let s = preferences.strings
        VStack(spacing: 10) {
            // 程序包里的 App 图标（scripts/make_icon.swift 生成）
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Sysmon")
                .font(.title2.bold())
            Text(s(.aboutVersion, version))
                .foregroundStyle(.secondary)
            Text(s[.aboutTagline])
                .multilineTextAlignment(.center)
            Link(Self.repoURL.absoluteString.replacingOccurrences(of: "https://", with: ""), destination: Self.repoURL)
        }
        .padding(24)
        .frame(width: 360)
        .navigationTitle(s[.aboutTitle])
    }
}
