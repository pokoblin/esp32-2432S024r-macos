import Foundation

/// Mac 端界面支持的语言。rawValue 是语言标识，存进设置里。
/// 板子上的文字不跟着变，固件只有中文。
public enum AppLanguage: String, CaseIterable, Codable, Sendable {
    case en
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case ja, ko, es, fr, de
    case ptBR = "pt-BR"
    case ru

    /// 语言自己的写法，放在语言下拉框里
    public var nativeName: String {
        switch self {
        case .en: "English"
        case .zhHans: "简体中文"
        case .zhHant: "繁體中文"
        case .ja: "日本語"
        case .ko: "한국어"
        case .es: "Español"
        case .fr: "Français"
        case .de: "Deutsch"
        case .ptBR: "Português (Brasil)"
        case .ru: "Русский"
        }
    }
}

/// 按系统的首选语言顺序挑第一个支持的；一个都不支持时用英文。
/// 中文按书写系统分：Hant、台湾、香港、澳门用繁体，其余用简体；葡萄牙文都用巴西葡萄牙文。
public func resolveLanguage(preferred: [String]) -> AppLanguage {
    for identifier in preferred {
        let parts = identifier.split(separator: "-").map { $0.lowercased() }
        guard let base = parts.first else { continue }
        switch base {
        case "zh":
            let traditional = parts.dropFirst().contains { ["hant", "tw", "hk", "mo"].contains($0) }
            return traditional ? .zhHant : .zhHans
        case "pt": return .ptBR
        default:
            if let lang = AppLanguage(rawValue: base) { return lang }
        }
    }
    return .en
}

/// 界面上每一条文字的键。带 %d / %@ 的条目用 Strings 的调用形式传参数。
public enum L10nKey: String, CaseIterable, Sendable {
    case menuConnected, menuNoDevice, menuStartFocus, menuPause, menuResume, menuSkip, menuResetRound
    case menuSettings, menuAbout, menuQuit
    case tabGeneral, tabPomodoro, tabHealth, tabUsage
    case generalSwitchScreen, generalShortcut, generalSwitchHelp, generalLed, generalLedHelp
    case generalLaunchAtLogin, generalLanguage, generalSystemLanguage
    case hotkeyTaken, hotkeyDuplicate, hotkeyRecording, hotkeyChange, hotkeySet, hotkeyClear
    case pomoScreen, pomoShortcut, pomoShortcutHelp, pomoDurations, pomoFocus, pomoShort, pomoLong
    case pomoRounds, pomoDurationsHelp
    case healthSit, healthWater, healthEvery, healthHelp
    case usageSection, usageClaude, usageChatGPT, usageSource, usageCost
    case statusOk, statusExpired, statusError, statusMissing
    case ageNow, ageMinutes, ageHours, ageDays
    case iconConnected, iconDisconnected
    case aboutTitle, aboutVersion, aboutTagline
}

/// 某一种语言的文字表。缺的条目退回英文。
public struct Strings: Sendable {
    public let language: AppLanguage

    public init(_ language: AppLanguage) {
        self.language = language
    }

    public subscript(_ key: L10nKey) -> String {
        Self.table(language)[key] ?? Self.table(.en)[key] ?? key.rawValue
    }

    /// 带参数的条目：按顺序填进 %d / %@
    public func callAsFunction(_ key: L10nKey, _ args: CVarArg...) -> String {
        String(format: self[key], locale: Locale(identifier: language.rawValue), arguments: args)
    }

    static func table(_ language: AppLanguage) -> [L10nKey: String] {
        switch language {
        case .en: english
        case .zhHans: simplifiedChinese
        case .zhHant: traditionalChinese
        case .ja: japanese
        case .ko: korean
        case .es: spanish
        case .fr: french
        case .de: german
        case .ptBR: brazilianPortuguese
        case .ru: russian
        }
    }
}
