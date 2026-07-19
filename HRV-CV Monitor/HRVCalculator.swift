import Foundation

// MARK: - HRV Day
struct HRVDay: Identifiable {
    let id        = UUID()
    let date      : Date
    let label     : String   // e.g. "Jul 16"
    let hrv       : Double   // rMSSD in ms
    let recovery  : Int      // 0–100
}

// MARK: - Trend Point
// One point on the HRV-CV sparkline: a rolling 7-night window ending on `date`.
struct TrendPoint: Identifiable {
    let id = UUID()
    let date        : Date
    let label       : String   // window end day, e.g. "Jul 16"
    let cv          : Double    // 7-night HRV-CV ending that day
    let avgRecovery : Int       // average WHOOP recovery over that window
}

// MARK: - CV Result
struct HRVCVResult {
    let days    : [HRVDay]   // 7 days, oldest first
    let mean    : Double
    let sd      : Double
    let cv      : Double     // percentage
    let window  : String     // e.g. "Jul 10 – Jul 16"
    let previousCV   : Double?  // 7-night CV for the prior week, if available
    let previousMean : Double?  // 7-night mean HRV for the prior week, if available
    let cvHistory    : [TrendPoint] // rolling 7-night CV over recent days (oldest → newest)

    var cvFormatted   : String { String(format: "%.1f%%", cv) }
    var meanFormatted : String { String(format: "%.1f ms", mean) }
    var sdFormatted   : String { String(format: "%.1f ms", sd) }

    var tier: Tier {
        if cv <= 8  { return .elite }
        if cv <= 15 { return .target }
        return .reducing
    }

    enum Tier: String {
        case elite    = "Elite"
        case target   = "On Track"
        case reducing = "Elevated"
    }

    // Combined verdict: the HRV-CV tier read together with the baseline direction.
    // This is what makes "elevated" meaningful — a wider swing while the baseline
    // rises is leveling up (good); while it falls is destabilizing (a warning).
    enum Verdict { case elite, onTrack, levelingUp, elevated, destabilizing }

    var verdict: Verdict {
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
    var statusHeadline: String {
        switch verdict {
        case .elite:         return "Elite consistency"
        case .onTrack:       return "On track"
        case .levelingUp:    return "Leveling up"
        case .elevated:      return "Running elevated"
        case .destabilizing: return "Destabilizing"
        }
    }

    /// One-line explanation and next step for the current verdict.
    var statusDetail: String {
        switch verdict {
        case .elite:
            return "Your HRV is remarkably steady night to night."
        case .onTrack:
            return "Consistent recovery. Under 8% is elite territory."
        case .levelingUp:
            return "Your HRV baseline is climbing, so this week's wider swing is the shift to a higher level, not instability. It should settle as the new baseline holds."
        case .elevated:
            return "Your HRV is swinging more than usual. Under 15% is the steadier range."
        case .destabilizing:
            return "Your HRV is swinging more and the baseline is dropping, which can signal accumulating fatigue or stress. A good week to ease off."
        }
    }

    // Week-over-week direction of the CV. Lower CV is better, so `improving`
    // means the CV fell versus the prior 7-night window.
    enum Trend { case improving, worsening, flat }

    var trend: Trend {
        guard let prev = previousCV else { return .flat }
        let delta = cv - prev
        if delta < -0.5 { return .improving }
        if delta >  0.5 { return .worsening }
        return .flat
    }

    var trendDelta: Double? { previousCV.map { cv - $0 } }

    // Direction of the HRV baseline (mean) vs the prior week: +1 up (better),
    // -1 down, 0 flat. Reading CV alongside this resolves the "rising CV is bad?"
    // ambiguity — CV up with baseline up is levelling up, not destabilising.
    var baselineDirection: Int? {
        guard let pm = previousMean else { return nil }
        let d = mean - pm
        if d >  1 { return  1 }
        if d < -1 { return -1 }
        return 0
    }
}

// MARK: - Calculator
enum HRVCalculator {

    /// Returns the HRV-CV result for the most recent valid 7-night consecutive window,
    /// or nil if fewer than 7 valid records are available.
    static func calculate(from records: [Recovery]) -> HRVCVResult? {
        let isoFull = ISO8601DateFormatter()
        isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let isoBasic = ISO8601DateFormatter()  // fallback without fractional seconds

        let display = DateFormatter()
        display.dateFormat = "MMM d"

        // Parse records into HRVDay values, filter valid HRV, sort oldest first
        let parsed: [HRVDay] = records.compactMap { rec in
            guard rec.scoreState == "SCORED",
                  let hrv = rec.score?.hrvRmssdMilli, hrv > 0,
                  let recovery = rec.score?.recoveryScore else { return nil }

            let date = isoFull.date(from: rec.createdAt) ?? isoBasic.date(from: rec.createdAt)
            guard let date else { return nil }

            return HRVDay(
                date:     date,
                label:    display.string(from: date),
                hrv:      hrv,
                recovery: recovery
            )
        }.sorted { $0.date < $1.date }

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

        // Rolling 7-night CV over recent days (oldest to newest), for the sparkline.
        // Each point carries its window-end date and average recovery for hover.
        var cvHistory: [TrendPoint] = []
        for end in 7...parsed.count {
            let win = parsed[(end - 7)..<end]
            guard let s = stats(of: win) else { continue }
            let endDay = parsed[end - 1]
            let avgRec = Int((win.map { Double($0.recovery) }.reduce(0, +) / Double(win.count)).rounded())
            cvHistory.append(TrendPoint(date: endDay.date, label: endDay.label,
                                        cv: s.cv, avgRecovery: avgRec))
        }
        if cvHistory.count > 14 { cvHistory = Array(cvHistory.suffix(14)) }

        return HRVCVResult(days: window, mean: current.mean, sd: current.sd,
                           cv: current.cv, window: windowLabel,
                           previousCV: previousCV, previousMean: previousMean,
                           cvHistory: cvHistory)
    }

    /// Sample mean, standard deviation, and coefficient of variation (%) for a set of nights.
    private static func stats<S: Sequence>(of days: S) -> (mean: Double, sd: Double, cv: Double)?
        where S.Element == HRVDay {
        let values = days.map(\.hrv)
        guard values.count >= 2 else { return nil }
        let mean = values.reduce(0, +) / Double(values.count)
        guard mean > 0 else { return nil }
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count - 1)
        let sd = sqrt(variance)
        return (mean, sd, (sd / mean) * 100)
    }
}
