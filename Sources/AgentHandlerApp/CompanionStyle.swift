import Foundation

enum CompanionStyle: String, CaseIterable, Identifiable {
    case menuBar, notch
    static let preferenceKey = "companionStyle.v1"
    var id: String { rawValue }
    var title: String { self == .notch ? "Notch" : "Menu bar" }
    func effective(hasNotch: Bool) -> Self { self == .notch && hasNotch ? .notch : .menuBar }
    static func load(from defaults: UserDefaults) -> Self {
        defaults.string(forKey: preferenceKey).flatMap(Self.init(rawValue:)) ?? .menuBar
    }
    func save(to defaults: UserDefaults) { defaults.set(rawValue, forKey: Self.preferenceKey) }
}
