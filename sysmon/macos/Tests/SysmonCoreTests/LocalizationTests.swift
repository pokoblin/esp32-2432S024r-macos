import Foundation
import Testing
@testable import SysmonCore

@Test func resolvesSystemLanguages() {
    #expect(resolveLanguage(preferred: ["zh-Hans-CN"]) == .zhHans)
    #expect(resolveLanguage(preferred: ["zh-CN"]) == .zhHans)
    #expect(resolveLanguage(preferred: ["zh-Hant-TW"]) == .zhHant)
    #expect(resolveLanguage(preferred: ["zh-HK"]) == .zhHant)
    #expect(resolveLanguage(preferred: ["zh-TW"]) == .zhHant)
    #expect(resolveLanguage(preferred: ["pt-PT"]) == .ptBR)
    #expect(resolveLanguage(preferred: ["ja-JP"]) == .ja)
    #expect(resolveLanguage(preferred: ["en-GB"]) == .en)
    // 第一个不支持就看下一个，都不支持用英文
    #expect(resolveLanguage(preferred: ["ar-SA", "fr-FR"]) == .fr)
    #expect(resolveLanguage(preferred: ["ar"]) == .en)
    #expect(resolveLanguage(preferred: []) == .en)
}

@Test func everyLanguageHasEveryString() {
    #expect(AppLanguage.allCases.count == 10)
    for lang in AppLanguage.allCases {
        let table = Strings.table(lang)
        for key in L10nKey.allCases {
            #expect(!(table[key] ?? "").isEmpty, "\(lang.rawValue) 缺 \(key.rawValue)")
        }
    }
}

/// 每条翻译的 %d / %@ 个数和顺序要和英文一致，否则 String(format:) 会出错
@Test func placeholdersMatchEnglish() {
    func placeholders(_ s: String) -> [String] {
        s.matches(of: /%[@d]/).map { String($0.output) }
    }
    let en = Strings.table(.en)
    for lang in AppLanguage.allCases {
        for key in L10nKey.allCases {
            #expect(placeholders(Strings.table(lang)[key] ?? "") == placeholders(en[key] ?? ""),
                    "\(lang.rawValue) \(key.rawValue)")
        }
    }
}

@Test func nativeNamesAreDistinct() {
    #expect(Set(AppLanguage.allCases.map(\.nativeName)).count == 10)
    #expect(AppLanguage.ja.nativeName == "日本語")
}

@Test func formatsWithArguments() {
    #expect(Strings(.en)(.pomoFocus, 25) == "Focus 25 min")
    #expect(Strings(.zhHans)(.pomoFocus, 25) == "专注 25 分钟")
    #expect(Strings(.en)(.menuConnected, "/dev/cu.x") == "Connected to /dev/cu.x")
}

@Test func settingsStatusInEnglish() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let en = Strings(.en)
    #expect(settingsStatus(UsageState(status: .ok, snapshot: UsageSnapshot(fetchedAt: now - 180)), now: now,
                           strings: en) == "OK · updated 3 min ago")
    #expect(settingsStatus(UsageState(), now: now, strings: en) == "Not signed in")
}
