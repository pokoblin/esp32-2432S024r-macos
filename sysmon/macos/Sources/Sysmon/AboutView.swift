import SwiftUI

/// 关于窗口：图标、名字、版本号、一句简介和 GitHub 地址。
/// 版本号从程序包的 Info.plist 读（由 scripts/bundle.sh 写入），直接 swift run 时显示 dev。
struct AboutView: View {
    static let repoURL = URL(string: "https://github.com/pokoblin/esp32-2432S024r-macos")!

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: BoardIcon.image(connected: true))
                .resizable()
                .renderingMode(.template)
                .frame(width: 64, height: 64)
                .foregroundStyle(.secondary)
            Text("Sysmon")
                .font(.title2.bold())
            Text("版本 \(version)")
                .foregroundStyle(.secondary)
            Text("把 ESP32-2432S024R 变成 Mac 的系统状态副屏")
                .multilineTextAlignment(.center)
            Link(Self.repoURL.absoluteString.replacingOccurrences(of: "https://", with: ""), destination: Self.repoURL)
        }
        .padding(24)
        .frame(width: 360)
    }
}
