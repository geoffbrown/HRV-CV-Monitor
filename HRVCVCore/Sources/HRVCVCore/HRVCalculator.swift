import Foundation

// MARK: - HRV Day
public struct HRVDay: Identifiable {
    public let id        = UUID()
    public let date      : Date
    public let label     : String   // e.g. "Jul 16"
    public let hrv       : Double   // rMSSD in ms
    public let recovery  : Int      // 0–100
    public let restingHR : Double?  // resting heart rate (bpm), nil if absent
}

// MARK: - HRV Series Point
// One night of the evidence chart: the nightly HRV plus the rolling baseline
// (mean) and spread (sd) over the trailing week — the "expected range".
public struct HRVSeriesPoint: Identifiable {
    public let id = UUID()
    public let date     : Date
    public let label    : String
    public let hrv      : Double
    public let mean     : Double   // rolling baseline
    public let sd       : Double   // rolling spread (half the expected range)
    public let recovery : Int
}

// MARK: - CV Result
public struct HRVCVResult {
    public let days    : [HRVDay]   // 7 days, oldest first
    public let mean    : Double
    public let sd      : Double
    public let cv      : Double     // percentage
    public let window  : String     // e.g. "Jul 10 – Jul 16"
    public let previousCV   : Double?  // 7-night CV for the prior week, if available
    public let previousMean : Double?  // 7-night mean HRV for the prior week, if available
    public let hrvSeries    : [HRVSeriesPoint] // nightly HRV + rolling baseline, for the evidence chart
    public let avgRecovery  : Int          // average WHOOP recovery over the window

    // WHOOP's own sleep_consistency_percentage, averaged over the same nights
    // as the HRV window (and the 7 nights before that). nil when sleep data
    // isn't available (scope not granted yet, or no matching records).
    public let avgSleepConsistency      : Int?
    public let previousSleepConsistency : Int?

    /// Direction of sleep consistency vs the prior window: +1 more regular,
    /// -1 less regular, 0 flat, nil if there isn't a prior window to compare.
    public var sleepConsistencyDirection: Int? {
        guard let cur = avgSleepConsistency, let prev = previousSleepConsistency else { return nil }
        let d = cur - prev
        if d > 3  { return  1 }
        if d < -3 { return -1 }
        return 0
    }

    // Resting heart rate (bpm), averaged over the same nights as the HRV window
    // and the 7 before it. From the recovery records we already fetch. nil when
    // WHOOP didn't score an RHR for those nights.
    public let avgRestingHR      : Int?
    public let previousRestingHR : Int?

    /// Raw direction of resting HR vs the prior window: +1 higher, -1 lower,
    /// 0 flat (threshold 2 bpm). NOTE the reading is direction-only — lower RHR
    /// is the good direction, but that judgment lives in the view, not here.
    public var restingHRDirection: Int? {
        guard let cur = avgRestingHR, let prev = previousRestingHR else { return nil }
        let d = cur - prev
        if d > 2  { return  1 }
        if d < -2 { return -1 }
        return 0
    }

    public var cvFormatted   : String { String(format: "%.1f%%", cv) }
    public var meanFormatted : String { String(format: "%.1f ms", mean) }
    public var sdFormatted   : String { String(format: "%.1f ms", sd) }

    public var tier: Tier {
        if cv <= 8  { return .elite }
        if cv <= 15 { return .target }
        return .reducing
    }

    public enum Tier: String {
        case elite    = "Elite"
        case target   = "On Track"
        case reducing = "Elevated"
    }

    // Combined verdict: the HRV-CV tier read together with the baseline direction.
    // This is what makes "elevated" meaningful — a wider swing while the baseline
    // rises is leveling up (good); while it falls is destabilizing (a warning).
    public enum Verdict { case elite, onTrack, levelingUp, elevated, destabilizing }

    public var verdict: Verdict {
        switch tier {
        case .elite:  return .elite
        case .target: return .onTrack
        case .reducing:
            switch baselineDirection {
            case .some(1):  return .levelingUp
            case .some(-1): return .destabilizing
            default:        return .elevated
            }
        }
    }

    /// Short status headline for the current verdict.
    public var statusHeadline: String {
        switch verdict {
        case .elite:         return "Elite consistency"
        case .onTrack:       return "On track"
        case .levelingUp:    return "Leveling up"
        case .elevated:      return "Running elevated"
        case .destabilizing: return "Destabilizing"
        }
    }

    /// One-line explanation and next step for the current verdict.
    public var statusDetail: String {
        switch verdict {
        case .elite:
            return "Your HRV is remarkably steady night to night."
        case .onTrack:
            return "Consistent recovery. Under 8% is elite territory."
        case .levelingUp:
            return "Baseline is climbing, so the wider swing is a step up, not instability."
        case .elevated:
            return "Swinging more than usual. Under 15% is the steadier range."
        case .destabilizing:
            return "Wider swings with a falling baseline can signal fatigue. Ease off this week."
        }
    }

    // Week-over-week change of the CV vs the prior 7-night window (signed).
    // Lower CV is better, so negative = improving.
    public var trendDelta: Double? { previousCV.map { cv - $0 } }

    // Direction of the HRV baseline (mean) vs the prior week: +1 up (better),
    // -1 down, 0 flat. Reading CV alongside this resolves the "rising CV is bad?"
    // ambiguity — CV up with baseline up is levelling up, not destabilising.
    public var baselineDirection: Int? {
        guard let pm = previousMean else { return nil }
        let d = mean - pm
        if d >  1 { return  1 }
        if d < -1 { return -1 }
        return 0
    }

    /// HRV baseline change vs the prior week, in ms (signed).
    public var baselineDeltaMs: Double? { previousMean.map { mean - $0 } }

    /// Short, verdict-forward label for the gauge (leads with meaning).
    public var verdictLabel: String {
        switch verdict {
        case .elite:         return "ELITE"
        case .onTrack:       return "ON TRACK"
        case .levelingUp:    return "LEVELING UP"
        case .elevated:      return "ELEVATED"
        case .destabilizing: return "DESTABILIZING"
        }
    }
}

// MARK: - Calculator
public enum HRVCalculator {

    /// Returns the HRV-CV result for the most recent valid 7-night consecutive window,
    /// or nil if fewer than 7 valid records are available. `sleep` is optional —
    /// pass an empty array (or omit it) if the sleep scope hasn't been granted
    /// yet; the sleep consistency signal just won't be populated.
    public static func calculate(from records: [Recovery], sleep: [Sleep] = []) -> HRVCVResult? {
        let isoFull = ISO8601DateFormatter()
        isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let isoBasic = ISO8601DateFormatter()  // fallback without fractional seconds

        let display = DateFormatter()
        display.dateFormat = "MMM d"

        // Parse records into HRVDay values, filter valid HRV, sort oldest first
        let allParsed: [HRVDay] = records.compactMap { rec in
            guard rec.scoreState == "SCORED",
                  let hrv = rec.score?.hrvRmssdMilli, hrv > 0,
                  let recovery = rec.score?.recoveryScore else { return nil }

            let date = isoFull.date(from: rec.createdAt) ?? isoBasic.date(from: rec.createdAt)
            guard let date else { return nil }

            return HRVDay(
                date:      date,
                label:     display.string(from: date),
                hrv:       hrv,
                recovery:  recovery,
                restingHR: rec.score?.restingHeartRate
            )
        }.sorted { $0.date < $1.date }

        // Keep one record per calendar day (the latest), so an updated or extra
        // recovery for the same day can't double-count a night in the window.
        var byDay: [Date: HRVDay] = [:]
        for day in allParsed { byDay[Calendar.current.startOfDay(for: day.date)] = day }
        let parsed = byDay.values.sorted { $0.date < $1.date }

        guard parsed.count >= 7, let current = stats(of: parsed.suffix(7)) else { return nil }

        // Take most recent 7
        let window = Array(parsed.suffix(7))
        let windowLabel = "\(window.first!.label) – \(window.last!.label)"

        // Prior week: the 7 nights immediately before the current window.
        var previousCV: Double?
        var previousMean: Double?
        if parsed.count >= 14 {
            let prior = parsed[(parsed.count - 14)..<(parsed.count - 7)]
            if let s = stats(of: prior) { previousCV = s.cv; previousMean = s.mean }
        }

        // Nightly HRV series with a rolling baseline (trailing up to 7 nights),
        // for the evidence chart — the last 14 nights.
        var hrvSeries: [HRVSeriesPoint] = []
        let seriesCount = min(parsed.count, 14)
        for i in (parsed.count - seriesCount)..<parsed.count {
            let win = Array(parsed[max(0, i - 6)...i])
            let vals = win.map(\.hrv)
            let m = vals.reduce(0, +) / Double(vals.count)
            // Population SD (divide by N), consistent with `stats` above.
            let sd = (vals.map { pow($0 - m, 2) }.reduce(0, +) / Double(vals.count)).squareRoot()
            hrvSeries.append(HRVSeriesPoint(date: parsed[i].date, label: parsed[i].label,
                                            hrv: parsed[i].hrv, mean: m, sd: sd,
                                            recovery: parsed[i].recovery))
        }

        let avgRecovery = Int((window.map { Double($0.recovery) }.reduce(0, +) / Double(window.count)).rounded())

        // One sleep_consistency_percentage per calendar day (naps and
        // unscored nights excluded, latest wins), matched against the same
        // date ranges as the HRV window and the prior one.
        var sleepByDay: [Date: Double] = [:]
        for rec in sleep {
            guard !rec.nap, rec.scoreState == "SCORED",
                  let consistency = rec.score?.sleepConsistencyPercentage,
                  let date = isoFull.date(from: rec.createdAt) ?? isoBasic.date(from: rec.createdAt)
            else { continue }
            sleepByDay[Calendar.current.startOfDay(for: date)] = consistency
        }
        let avgSleepConsistency = averageConsistency(sleepByDay, from: window.first!.date, to: window.last!.date)
        var previousSleepConsistency: Double?
        if parsed.count >= 14 {
            let prior = parsed[(parsed.count - 14)..<(parsed.count - 7)]
            previousSleepConsistency = averageConsistency(sleepByDay, from: prior.first!.date, to: prior.last!.date)
        }

        // Resting HR over the same windows (from the recovery records above).
        let avgRestingHR = averageRestingHR(of: window)
        var previousRestingHR: Double?
        if parsed.count >= 14 {
            previousRestingHR = averageRestingHR(of: parsed[(parsed.count - 14)..<(parsed.count - 7)])
        }

        return HRVCVResult(days: window, mean: current.mean, sd: current.sd,
                           cv: current.cv, window: windowLabel,
                           previousCV: previousCV, previousMean: previousMean,
                           hrvSeries: hrvSeries, avgRecovery: avgRecovery,
                           avgSleepConsistency: avgSleepConsistency.map { Int($0.rounded()) },
                           previousSleepConsistency: previousSleepConsistency.map { Int($0.rounded()) },
                           avgRestingHR: avgRestingHR.map { Int($0.rounded()) },
                           previousRestingHR: previousRestingHR.map { Int($0.rounded()) })
    }

    /// Average of the non-nil resting-HR values across a set of nights. nil if none.
    private static func averageRestingHR<S: Sequence>(of days: S) -> Double?
        where S.Element == HRVDay {
        let vals = days.compactMap(\.restingHR)
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }

    /// Average of the sleep-consistency values whose calendar day falls within
    /// [start, end] inclusive. nil if none fall in range.
    private static func averageConsistency(_ byDay: [Date: Double], from start: Date, to end: Date) -> Double? {
        let cal = Calendar.current
        let startDay = cal.startOfDay(for: start)
        let endDay = cal.startOfDay(for: end)
        let vals = byDay.compactMap { date, value in
            (date >= startDay && date <= endDay) ? value : nil
        }
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }

    /// Mean, standard deviation, and coefficient of variation (%) for a set of
    /// nights. Uses the POPULATION standard deviation (divide by N, not N-1):
    /// the 7 nights are the whole window of interest, not a sample from a larger
    /// set, and — critically — this matches WHOOP / Marco Altini's HRV4Training
    /// definition of HRV-CV. Dividing by N-1 (sample SD) inflates CV by a factor
    /// of sqrt(N/(N-1)) ≈ 1.08 for a 7-night window, which is exactly the gap
    /// that made this read ~15% where WHOOP Coach reads 13.7%. Do not "correct"
    /// this back to N-1 — it would re-break parity with WHOOP.
    private static func stats<S: Sequence>(of days: S) -> (mean: Double, sd: Double, cv: Double)?
        where S.Element == HRVDay {
        let values = days.map(\.hrv)
        guard values.count >= 2 else { return nil }
        let mean = values.reduce(0, +) / Double(values.count)
        guard mean > 0 else { return nil }
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count)
        let sd = sqrt(variance)
        return (mean, sd, (sd / mean) * 100)
    }
}
