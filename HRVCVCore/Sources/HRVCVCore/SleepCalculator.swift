import Foundation

// MARK: - Sleep Night
// One night's sleep timing: when you fell asleep and woke, plus WHOOP's own
// consistency score for that night.
public struct SleepNight: Identifiable {
    public let id = UUID()
    public let date        : Date      // calendar day the sleep ended (wake day)
    public let label       : String    // e.g. "Jul 23"
    public let onset       : Date      // sleep start
    public let wake        : Date      // sleep end
    public let consistency : Double?   // WHOOP sleep_consistency_percentage, if scored

    // Plottable times for the bed/wake chart: minutes on the night-centered axis
    // (noon = 0), so onsets either side of midnight stay contiguous.
    public var onsetClockMin: Double { SleepCalculator.clockMinutes(onset) }
    public var wakeClockMin:  Double { SleepCalculator.clockMinutes(wake) }
}

// MARK: - Which schedule edge is the lever
public enum SleepAnchor { case bedtime, wake, neither }

// MARK: - Sleep Result
// The focused sleep-consistency picture: WHOOP's headline consistency, and OUR
// derived evidence — how much bedtime and wake time drift over the window, and
// the single highest-impact anchor to steady. Everything is in service of the
// HRV-CV story (irregular timing is the usual cause of a widening HRV swing).
public struct SleepResult {
    public let nights   : [SleepNight]   // up to the last 14, oldest first (for the chart)
    public let window   : [SleepNight]   // the most recent 7, oldest first (for stats)

    // WHOOP's own consistency: the most recent scored night's value, and the
    // 7-night average (our trend), plus the prior 7-night average for direction.
    public let latestConsistency   : Int?
    public let avgConsistency      : Int?
    public let previousConsistency : Int?

    // Our derived drift over the 7-night window: the spread (SD) of bedtime and
    // wake time, in minutes. Lower = steadier.
    public let bedtimeDriftMin : Double
    public let wakeDriftMin    : Double

    // Median clock times over the window (the anchor targets), as minutes-of-day
    // on a night-centered axis (see clockMinutes). Rendered via medianBedtimeText.
    public let medianBedtimeMin : Double
    public let medianWakeMin    : Double

    // MARK: Derived reads

    /// Direction of WHOOP consistency vs the prior week: +1 steadier, -1 less
    /// steady, 0 flat (threshold 3 points). nil without a prior window.
    public var consistencyDirection: Int? {
        guard let cur = avgConsistency, let prev = previousConsistency else { return nil }
        let d = cur - prev
        if d > 3  { return  1 }
        if d < -3 { return -1 }
        return 0
    }

    /// Tier from WHOOP's framing (avg member ~68%): tight ≥80, drifting 60-80,
    /// erratic <60. Higher is better (opposite of HRV-CV).
    public enum Tier: String { case tight = "Steady", drifting = "Drifting", erratic = "Erratic" }
    public var tier: Tier? {
        guard let c = latestConsistency ?? avgConsistency else { return nil }
        if c >= 80 { return .tight }
        if c >= 60 { return .drifting }
        return .erratic
    }

    /// The higher-impact edge to steady: whichever of bedtime / wake drifts more
    /// (and only if that drift is meaningful, > 20 min). This drives the one
    /// recommendation the view shows.
    public var lever: SleepAnchor {
        let worst = max(bedtimeDriftMin, wakeDriftMin)
        guard worst > 20 else { return .neither }
        return bedtimeDriftMin >= wakeDriftMin ? .bedtime : .wake
    }

    /// The recommendation's anchor target as a clock string, e.g. "11:20 PM".
    public var medianBedtimeText: String { SleepResult.clockText(medianBedtimeMin) }
    public var medianWakeText: String    { SleepResult.clockText(medianWakeMin) }

    // Minutes are measured on a NIGHT-CENTERED axis: minutes past noon, so an
    // 11 PM bedtime is 660 and a 1 AM bedtime is 780 (no midnight wrap to break
    // the spread/median). Convert back to a 12-hour clock string for display.
    public static func clockText(_ minutesPastNoon: Double) -> String {
        let total = Int((minutesPastNoon).rounded()) % (24 * 60)
        let minsFromMidnight = (12 * 60 + total) % (24 * 60)
        var hour = minsFromMidnight / 60
        let minute = minsFromMidnight % 60
        let ampm = hour < 12 ? "AM" : "PM"
        hour %= 12
        if hour == 0 { hour = 12 }
        return String(format: "%d:%02d %@", hour, minute, ampm)
    }
}

// MARK: - Calculator
public enum SleepCalculator {

    /// Builds the sleep-timing picture from WHOOP sleep records (naps excluded),
    /// or nil if fewer than 7 valid nights are available. Deliberately uses the
    /// same rolling 7-night window as HRVCalculator so the two views agree.
    public static func calculate(from sleep: [Sleep]) -> SleepResult? {
        let isoFull = ISO8601DateFormatter()
        isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()
        let display = DateFormatter()
        display.dateFormat = "MMM d"

        func parse(_ s: String) -> Date? { isoFull.date(from: s) ?? isoBasic.date(from: s) }

        let parsed: [SleepNight] = sleep.compactMap { rec in
            guard !rec.nap, rec.scoreState == "SCORED",
                  let onset = parse(rec.start), let wake = parse(rec.end) else { return nil }
            return SleepNight(date: wake, label: display.string(from: wake),
                              onset: onset, wake: wake,
                              consistency: rec.score?.sleepConsistencyPercentage)
        }.sorted { $0.wake < $1.wake }

        // One night per calendar day (latest wins), matching HRVCalculator hygiene.
        var byDay: [Date: SleepNight] = [:]
        for n in parsed { byDay[Calendar.current.startOfDay(for: n.wake)] = n }
        let nights = byDay.values.sorted { $0.wake < $1.wake }

        guard nights.count >= 7 else { return nil }

        let window = Array(nights.suffix(7))
        let prior  = nights.count >= 14 ? Array(nights[(nights.count - 14)..<(nights.count - 7)]) : []
        let chart  = Array(nights.suffix(14))

        // WHOOP consistency: latest scored value + window averages.
        let latest = window.reversed().compactMap(\.consistency).first
        let avg    = average(window.compactMap(\.consistency))
        let prev   = average(prior.compactMap(\.consistency))

        // Our derived drift: SD of onset/wake clock times (night-centered minutes).
        let onsetMins = window.map { clockMinutes($0.onset) }
        let wakeMins  = window.map { clockMinutes($0.wake) }

        return SleepResult(
            nights: chart,
            window: window,
            latestConsistency:   latest.map { Int($0.rounded()) },
            avgConsistency:      avg.map { Int($0.rounded()) },
            previousConsistency: prev.map { Int($0.rounded()) },
            bedtimeDriftMin: stdDev(onsetMins),
            wakeDriftMin:    stdDev(wakeMins),
            medianBedtimeMin: median(onsetMins),
            medianWakeMin:    median(wakeMins)
        )
    }

    /// Minutes past NOON for a timestamp's local time-of-day. Centering on noon
    /// keeps a night's sleep (roughly 10 PM–8 AM → 600–1200) contiguous, so
    /// bedtimes either side of midnight don't split the spread.
    static func clockMinutes(_ date: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let m = Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
        return m >= 12 * 60 ? m - 12 * 60 : m + 12 * 60   // shift so noon = 0
    }

    private static func average(_ v: [Double]) -> Double? {
        guard !v.isEmpty else { return nil }
        return v.reduce(0, +) / Double(v.count)
    }

    private static func stdDev(_ v: [Double]) -> Double {
        guard v.count >= 2 else { return 0 }
        let m = v.reduce(0, +) / Double(v.count)
        return (v.map { pow($0 - m, 2) }.reduce(0, +) / Double(v.count)).squareRoot()  // population, like HRV-CV
    }

    private static func median(_ v: [Double]) -> Double {
        guard !v.isEmpty else { return 0 }
        let s = v.sorted()
        let mid = s.count / 2
        return s.count % 2 == 0 ? (s[mid - 1] + s[mid]) / 2 : s[mid]
    }
}
