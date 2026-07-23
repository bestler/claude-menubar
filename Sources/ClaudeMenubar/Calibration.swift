import Foundation

/// Persists user calibrations that map raw token counts to the percentages
/// shown in the Claude app. There is no official quota API, so this is the
/// only way to display a meaningful "% used".
///
///     limit = currentTokens / (observedPercent / 100)
///     laterPercent = laterTokens / limit * 100
final class CalibrationStore {
    private let defaults: UserDefaults

    private enum Key {
        static let sessionLimit = "sessionLimit"
        static let weekLimit = "weekLimit"
        static let sessionCalibratedAt = "sessionCalibratedAt"
        static let weekCalibratedAt = "weekCalibratedAt"
        static let resetAt = "resetAt"
        static let resetCalibratedAt = "resetCalibratedAt"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Session

    /// Derived token ceiling for the session window, or nil if never calibrated.
    var sessionLimit: Double? {
        let v = defaults.double(forKey: Key.sessionLimit)
        return v > 0 ? v : nil
    }

    var sessionCalibratedAt: Date? {
        defaults.object(forKey: Key.sessionCalibratedAt) as? Date
    }

    /// Store a session calibration. `observedPercent` must be in (0, 100].
    @discardableResult
    func calibrateSession(currentTokens: Int, observedPercent: Double, now: Date = Date()) -> Bool {
        guard observedPercent > 0, observedPercent <= 100, currentTokens > 0 else { return false }
        defaults.set(Double(currentTokens) / (observedPercent / 100.0), forKey: Key.sessionLimit)
        defaults.set(now, forKey: Key.sessionCalibratedAt)
        return true
    }

    func clearSession() {
        defaults.removeObject(forKey: Key.sessionLimit)
        defaults.removeObject(forKey: Key.sessionCalibratedAt)
    }

    /// Session percentage for a token count, or nil if uncalibrated.
    func sessionPct(forTokens tokens: Int) -> Double? {
        guard let limit = sessionLimit, limit > 0 else { return nil }
        return Double(tokens) / limit * 100.0
    }

    // MARK: Week

    var weekLimit: Double? {
        let v = defaults.double(forKey: Key.weekLimit)
        return v > 0 ? v : nil
    }

    var weekCalibratedAt: Date? {
        defaults.object(forKey: Key.weekCalibratedAt) as? Date
    }

    @discardableResult
    func calibrateWeek(currentTokens: Int, observedPercent: Double, now: Date = Date()) -> Bool {
        guard observedPercent > 0, observedPercent <= 100, currentTokens > 0 else { return false }
        defaults.set(Double(currentTokens) / (observedPercent / 100.0), forKey: Key.weekLimit)
        defaults.set(now, forKey: Key.weekCalibratedAt)
        return true
    }

    func clearWeek() {
        defaults.removeObject(forKey: Key.weekLimit)
        defaults.removeObject(forKey: Key.weekCalibratedAt)
    }

    func weekPct(forTokens tokens: Int) -> Double? {
        guard let limit = weekLimit, limit > 0 else { return nil }
        return Double(tokens) / limit * 100.0
    }

    // MARK: Reset (session-window reset time)

    /// Absolute reset timestamp anchored from the last calibration, or nil.
    var resetAt: Date? {
        defaults.object(forKey: Key.resetAt) as? Date
    }

    var resetCalibratedAt: Date? {
        defaults.object(forKey: Key.resetCalibratedAt) as? Date
    }

    /// Anchor a reset from the "resets in X minutes" value shown by Claude Code.
    @discardableResult
    func calibrateReset(minutesFromNow: Int, now: Date = Date()) -> Bool {
        guard minutesFromNow > 0, minutesFromNow <= 5 * 60 else { return false }
        defaults.set(now.addingTimeInterval(Double(minutesFromNow) * 60), forKey: Key.resetAt)
        defaults.set(now, forKey: Key.resetCalibratedAt)
        return true
    }

    func clearReset() {
        defaults.removeObject(forKey: Key.resetAt)
        defaults.removeObject(forKey: Key.resetCalibratedAt)
    }

    /// Claude's session-limit window length. The countdown rolls by this amount
    /// each time it lapses, so a single calibration keeps working across windows.
    static let sessionWindowMinutes = 5 * 60

    /// Minutes until the (possibly rolled-forward) calibrated reset, or nil if
    /// never calibrated. Once the anchored reset passes we roll it forward in
    /// whole 5h windows rather than expiring — so it "resets" on its own.
    func calibratedRemainingMinutes(now: Date = Date()) -> Int? {
        guard var r = resetAt else { return nil }
        let window = TimeInterval(Self.sessionWindowMinutes * 60)
        while r <= now { r += window }
        return Int((r.timeIntervalSince(now) / 60).rounded())
    }

    /// True when the countdown is now a rolled-forward window rather than the
    /// originally-calibrated one (i.e. the anchor time has passed).
    func resetHasRolled(now: Date = Date()) -> Bool {
        guard let r = resetAt else { return false }
        return r <= now
    }
}
