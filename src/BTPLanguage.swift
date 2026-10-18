import SwiftUI
import AppKit

@MainActor
final class BTPLanguage: ObservableObject {
    static let shared = BTPLanguage()
    @Published var selection: String {
        didSet {
            UserDefaults.standard.set(selection, forKey: "BTPLanguage")
            if selection == "auto" { UserDefaults.standard.removeObject(forKey: "AppleLanguages") }
            else { UserDefaults.standard.set([code], forKey: "AppleLanguages") }
            NotificationCenter.default.post(name: .btpLanguageChanged, object: nil)
        }
    }
    var code: String {
        if selection != "auto" { return selection }
        // System languages, unaffected by an earlier BTP-only override.
        let languages = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String]
        return (languages?.first ?? Locale.preferredLanguages.first ?? "en").hasPrefix("pt") ? "pt-BR" : "en"
    }
    private init() { selection = UserDefaults.standard.string(forKey: "BTPLanguage") ?? "auto" }
}

extension Notification.Name { static let btpLanguageChanged = Notification.Name("BTPLanguageChanged") }

private let btpEnglish: [String: String] = {
    guard let url = Bundle.main.url(forResource: "Localizations", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let translations = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
    return translations
}()

// Messages remain in canonical Portuguese in the model. Translate at display
// time so changing language also refreshes an existing progress/error message.
@MainActor
func L(_ value: String, depth: Int = 0) -> String {
    guard BTPLanguage.shared.code == "en" else { return value }
    if let exact = btpEnglish[value] { return exact }
    guard depth < 3 else { return value }
    for (source, translation) in btpEnglish where source.contains("%@") {
        let pattern = "^" + source.components(separatedBy: "%@").map(NSRegularExpression.escapedPattern(for:)).joined(separator: "([\\s\\S]*?)") + "$"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { continue }
        var output = translation
        for index in 1..<match.numberOfRanges {
            guard let range = Range(match.range(at: index), in: value), let marker = output.range(of: "%@") else { continue }
            output.replaceSubrange(marker, with: L(String(value[range]), depth: depth + 1))
        }
        return output
    }
    return value
}

struct BTPText: View {
    let value: String
    @ObservedObject private var language = BTPLanguage.shared
    init(_ value: String) { self.value = value }
    var body: some View { Text(verbatim: L(value)).environment(\.locale, Locale(identifier: language.code)) }
}
