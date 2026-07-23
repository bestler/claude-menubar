import Foundation

// MARK: - Raw ccusage JSON shapes

/// `ccusage blocks --active --json` (and `blocks --json`).
struct BlocksResponse: Decodable {
    let blocks: [Block]
}

struct Block: Decodable {
    let isActive: Bool
    let isGap: Bool?
    let totalTokens: Int
    let costUSD: Double
    let endTime: String?
    let projection: Projection?
    let burnRate: BurnRate?
}

struct Projection: Decodable {
    let remainingMinutes: Int?
    let totalTokens: Int?
    let totalCost: Double?
}

struct BurnRate: Decodable {
    let costPerHour: Double?
    let tokensPerMinute: Double?
}

/// `ccusage weekly --json`.
struct WeeklyResponse: Decodable {
    let weekly: [WeekRow]
}

struct WeekRow: Decodable {
    let week: String?
    let totalTokens: Int
}

// MARK: - Derived snapshot consumed by the UI

/// A fully resolved view of usage at one moment, ready for display.
struct UsageSnapshot {
    var isActive: Bool
    var tokens: Int
    var cost: Double
    var costPerHour: Double?
    var tokensPerMinute: Double?
    /// Minutes until reset (calibrated value if available, else ccusage block estimate).
    var remainingMinutes: Int?
    /// True when `remainingMinutes` comes from a user calibration, false when it's the ccusage estimate.
    var resetCalibrated: Bool = false
    /// True when the calibrated countdown has rolled forward into a later window.
    var resetRolled: Bool = false

    /// Session percentage — only present when a calibration exists.
    var sessionPct: Double?
    var sessionCalibratedAt: Date?

    /// Week tracking — only present when week tracking is on and the call succeeds.
    var weekTokens: Int?
    var weekPct: Double?
    var weekCalibratedAt: Date?

    static func idle() -> UsageSnapshot {
        UsageSnapshot(isActive: false, tokens: 0, cost: 0)
    }

    init(isActive: Bool, tokens: Int, cost: Double,
         costPerHour: Double? = nil, tokensPerMinute: Double? = nil,
         remainingMinutes: Int? = nil,
         sessionPct: Double? = nil, sessionCalibratedAt: Date? = nil,
         weekTokens: Int? = nil, weekPct: Double? = nil, weekCalibratedAt: Date? = nil) {
        self.isActive = isActive
        self.tokens = tokens
        self.cost = cost
        self.costPerHour = costPerHour
        self.tokensPerMinute = tokensPerMinute
        self.remainingMinutes = remainingMinutes
        self.sessionPct = sessionPct
        self.sessionCalibratedAt = sessionCalibratedAt
        self.weekTokens = weekTokens
        self.weekPct = weekPct
        self.weekCalibratedAt = weekCalibratedAt
    }
}

// MARK: - Formatting helpers

enum Fmt {
    /// 7_237_348 -> "7.2M", 12_345 -> "12.3k"
    static func tokens(_ n: Int) -> String {
        let v = Double(n)
        if v >= 1_000_000 { return String(format: "%.1fM", v / 1_000_000) }
        if v >= 1_000 { return String(format: "%.1fk", v / 1_000) }
        return "\(n)"
    }

    static func cost(_ d: Double) -> String {
        String(format: "$%.2f", d)
    }

    static func costShort(_ d: Double) -> String {
        d >= 100 ? String(format: "$%.0f", d) : String(format: "$%.1f", d)
    }

    /// minutes -> "3h 5m" (or "45m")
    static func duration(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    /// minutes -> compact "3h05" / "45m" for the menu bar
    static func durationShort(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return h > 0 ? String(format: "%dh%02d", h, m) : "\(m)m"
    }

    static func pct(_ p: Double) -> String {
        String(format: "%.0f%%", p)
    }

    /// Parse a human "resets in" value into minutes.
    /// Accepts "1h8", "1h 8m", "1h08m", "1h", "1:08", "68", "68m".
    static func parseDurationMinutes(_ raw: String) -> Int? {
        let s = raw.lowercased().trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return nil }
        if s.contains(":") {
            let parts = s.split(separator: ":")
            guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
            return h * 60 + m
        }
        if let hRange = s.range(of: "h") {
            var total = 0
            let hPart = s[s.startIndex..<hRange.lowerBound].trimmingCharacters(in: .whitespaces)
            guard let h = Int(hPart) else { return nil }
            total += h * 60
            let after = s[hRange.upperBound...]
                .replacingOccurrences(of: "m", with: "")
                .trimmingCharacters(in: .whitespaces)
            if !after.isEmpty {
                guard let m = Int(after) else { return nil }
                total += m
            }
            return total
        }
        let mPart = s.replacingOccurrences(of: "m", with: "").trimmingCharacters(in: .whitespaces)
        return Int(mPart)
    }

    /// "2h ago" / "just now" for calibration age.
    static func ago(_ date: Date, now: Date = Date()) -> String {
        let secs = Int(now.timeIntervalSince(date))
        if secs < 60 { return "just now" }
        let mins = secs / 60
        if mins < 60 { return "\(mins)m ago" }
        let hrs = mins / 60
        if hrs < 24 { return "\(hrs)h ago" }
        return "\(hrs / 24)d ago"
    }
}
