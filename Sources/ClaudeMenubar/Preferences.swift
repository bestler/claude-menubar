import Foundation

/// Which metric is shown as the menu-bar title text.
enum BarMetric: String, CaseIterable {
    case cost
    case tokens
    case timeLeft
    case percent

    var menuLabel: String {
        switch self {
        case .cost: return "Cost"
        case .tokens: return "Tokens"
        case .timeLeft: return "Time left"
        case .percent: return "Percentage"
        }
    }
}

/// User-facing display and refresh preferences, persisted in UserDefaults.
final class Preferences {
    private let defaults: UserDefaults

    private enum Key {
        static let barMetric = "barMetric"
        static let refreshInterval = "refreshInterval"
        static let weekTracking = "weekTracking"
    }

    /// Refresh intervals offered in the menu, in seconds.
    static let refreshChoices: [Int] = [10, 15, 30, 60]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var barMetric: BarMetric {
        get { BarMetric(rawValue: defaults.string(forKey: Key.barMetric) ?? "") ?? .cost }
        set { defaults.set(newValue.rawValue, forKey: Key.barMetric) }
    }

    var refreshInterval: Int {
        get {
            let v = defaults.integer(forKey: Key.refreshInterval)
            return v > 0 ? v : 15
        }
        set { defaults.set(newValue, forKey: Key.refreshInterval) }
    }

    var weekTracking: Bool {
        get { defaults.bool(forKey: Key.weekTracking) }
        set { defaults.set(newValue, forKey: Key.weekTracking) }
    }
}
