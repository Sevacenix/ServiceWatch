import Foundation

enum AppLanguage: String, CaseIterable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    static let preferenceKey = "ServiceWatchLanguage"

    var title: String {
        switch self {
        case .system: tr("跟随系统")
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        }
    }

    func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> Self {
        guard self == .system else { return self }
        for identifier in preferredLanguages {
            switch Locale(identifier: identifier).language.languageCode?.identifier {
            case "en": return .english
            case "zh": return .simplifiedChinese
            default: continue
            }
        }
        return .english
    }

    var locale: Locale { Locale(identifier: resolved().rawValue) }

    static var current: Self {
        let preference = UserDefaults.standard.string(forKey: preferenceKey).flatMap(Self.init(rawValue:)) ?? .system
        return preference.resolved()
    }
}

enum L10n {
    struct Phrase: ExpressibleByStringInterpolation {
        let pattern: String
        let arguments: [String]

        init(stringLiteral value: String) {
            pattern = value
            arguments = []
        }

        init(stringInterpolation: Interpolation) {
            pattern = stringInterpolation.pattern
            arguments = stringInterpolation.arguments
        }

        struct Interpolation: StringInterpolationProtocol {
            var pattern = ""
            var arguments: [String] = []

            init(literalCapacity: Int, interpolationCount: Int) {
                pattern.reserveCapacity(literalCapacity)
                arguments.reserveCapacity(interpolationCount)
            }

            mutating func appendLiteral(_ literal: String) { pattern += literal }

            mutating func appendInterpolation<T>(_ value: T) {
                pattern += "{\(arguments.count)}"
                arguments.append(String(describing: value))
            }
        }
    }

    private static let english: [String: String] = {
        let url = Bundle.main.url(forResource: "English", withExtension: "json")
            ?? Bundle.module.url(forResource: "English", withExtension: "json")
        guard let url, let data = try? Data(contentsOf: url),
              let translations = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return translations
    }()

    private static let placeholder = try! NSRegularExpression(pattern: #"\{([0-9]+)\}"#)

    static func dateTime(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: AppLanguage.current.locale))
    }

    static func label(_ key: String, language: AppLanguage = .current) -> String {
        language.resolved() == .english ? english[key] ?? key : key
    }

    static func text(_ phrase: Phrase, language: AppLanguage = .current) -> String {
        let template = label(phrase.pattern, language: language)
        guard !phrase.arguments.isEmpty else { return template }
        let rendered = NSMutableString(string: template)
        for match in placeholder.matches(in: template, range: NSRange(location: 0, length: rendered.length)).reversed() {
            guard let range = Range(match.range(at: 1), in: template),
                  let index = Int(template[range]), phrase.arguments.indices.contains(index) else { continue }
            rendered.replaceCharacters(in: match.range, with: phrase.arguments[index])
        }
        return rendered as String
    }
}

func tr(_ phrase: L10n.Phrase) -> String { L10n.text(phrase) }
