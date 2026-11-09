import Foundation

extension Bundle {
    /// Where HueKit's texts come from.
    ///
    /// A resource bundle answers in the language its host app runs in. A host without
    /// localizations of its own (a command-line tool, the test runner) counts as
    /// English whatever the user prefers, so there the source language, German, is used.
    static let hueKit: Bundle = {
        let hostLanguages = Bundle.main.localizations.filter { $0 != "Base" }
        guard hostLanguages.isEmpty,
              let path = Bundle.module.path(forResource: "de", ofType: "lproj"),
              let german = Bundle(path: path)
        else { return .module }
        return german
    }()
}
