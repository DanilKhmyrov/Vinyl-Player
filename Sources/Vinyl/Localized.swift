import Foundation

enum Language: String, CaseIterable {
    case ru, en

    var name: String { self == .ru ? "Русский" : "English" }
}

enum L {
    static func t(_ ru: String, _ en: String) -> String {
        Preferences.language == .en ? en : ru
    }
}
