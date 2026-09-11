import Foundation

// MARK: - Demo Data
// Run with HRVCV_MOCK=1 to use a built-in dataset instead of WHOOP — handy for
// demoing the app without an account and for UI work without burning API calls.
// Variants (for exercising each verdict): HRVCV_MOCK=ontrack | destabilizing.
public enum MockData {
    private static var variant: String { ProcessInfo.processInfo.environment["HRVCV_MOCK"] ?? "" }
    public static var isEnabled: Bool { !variant.isEmpty && variant != "0" }

    public static func records() -> [Recovery] {
        let hrv: [Double], recovery: [Int], rhr: [Double]
        switch variant {
        case "ontrack":
            // Steady around 45 ms with moderate spread: CV ~9%, on track.
            hrv      = [43, 46, 41, 47, 44, 48, 42,
                        40, 48, 42, 50, 44, 49, 41]
            recovery = [72, 78, 66, 80, 74, 82, 70,
                        68, 81, 70, 85, 75, 83, 69]
            // Resting HR flat, matching the steady story.
            rhr      = [54, 53, 55, 54, 54, 53, 55,
                        54, 55, 53, 54, 55, 53, 54]
        case "destabilizing":
            // A tight ~51 ms week, then falling and swingy: CV ~17% with a
            // dropping baseline — the warning story.
            hrv      = [52, 50, 53, 51, 52, 50, 51,
                        50, 48, 38, 45, 30, 42, 35]
            recovery = [84, 80, 86, 82, 85, 81, 83,
                        70, 65, 44, 58, 30, 52, 40]
            // Resting HR climbing as things destabilize (up ~6 bpm) — a warning.
            rhr      = [50, 51, 49, 50, 51, 50, 49,
                        52, 54, 58, 56, 60, 57, 59]
        default:
            // Two contrasting weeks: a tight ~34 ms baseline, then a step up to
            // a higher but swingier ~44 ms week — the "leveling up" story.
            hrv      = [35, 33, 36, 34, 35, 32, 34,
                        33.6, 34.8, 58.2, 48.7, 53.9, 41.7, 37.4]
            recovery = [66, 61, 68, 64, 65, 60, 63,
                        57, 58, 97, 93, 96, 71, 55]
            // Resting HR settling lower as HRV levels up (down ~5 bpm) — good.
            rhr      = [58, 59, 57, 58, 58, 60, 59,
                        57, 56, 50, 52, 51, 54, 55]
        }
        let iso = ISO8601DateFormatter()
        return hrv.indices.map { i in
            let date = Calendar.current.date(byAdding: .day, value: i - (hrv.count - 1), to: Date())!
            return Recovery(cycleId: i,
                            createdAt: iso.string(from: date),
                            scoreState: "SCORED",
                            score: .init(recoveryScore: recovery[i], hrvRmssdMilli: hrv[i],
                                         restingHeartRate: rhr[i]))
        }
    }

    public static func sleepRecords() -> [Sleep] {
        // consistency = WHOOP's own score; bed/wakeDrift = minutes off a ~11 PM
        // lights-out / ~7 AM wake, per night. The drift arrays match each story:
        // steady schedule when consistency is high, scattered when it drops.
        let consistency: [Double], bedDrift: [Int], wakeDrift: [Int]
        switch variant {
        case "ontrack":
            // Steady bed/wake timing, matching the steady HRV story.
            consistency = [82, 80, 85, 81, 83, 84, 82,  83, 81, 84, 82, 85, 83, 84]
            bedDrift    = [-5, 8, -10, 3, -2, 6, -8,    5, -6, 2, -4, 7, -3, 4]
            wakeDrift   = [4, -6, 8, -3, 5, -7, 2,     -4, 6, -5, 3, -8, 4, -2]
        case "destabilizing":
            // Schedule erodes across the current week — the "why" behind the swing.
            consistency = [88, 86, 89, 87, 88, 86, 87,  80, 74, 62, 58, 45, 52, 48]
            bedDrift    = [-5, 6, -8, 4, -3, 7, -6,     25, -40, 60, -55, 95, -75, 45]
            wakeDrift   = [3, -5, 6, -4, 5, -6, 3,      20, -30, 45, -35, 65, -50, 30]
        default:
            // Moderate, mostly-bedtime drift — a "drifting" schedule.
            consistency = [90, 88, 91, 89, 90, 87, 89,  85, 79, 68, 71, 74, 76, 78]
            bedDrift    = [-30, 40, -50, 25, -35, 45, -20,  -22, 28, -30, 18, -25, 24, -15]
            wakeDrift   = [-15, 20, -25, 12, -18, 22, -10,   10, -12, 15, -8, 13, -11, 7]
        }
        let cal = Calendar.current
        let iso = ISO8601DateFormatter()
        let n = consistency.count
        return (0..<n).map { i in
            let wakeDay = cal.date(byAdding: .day, value: i - (n - 1), to: Date())!
            let midnight = cal.startOfDay(for: wakeDay)
            // wake ~07:00 (+drift) on the wake day; onset ~23:00 (+drift) the evening before.
            let wake  = cal.date(byAdding: .minute, value: 7 * 60 + wakeDrift[i], to: midnight)!
            let onset = cal.date(byAdding: .minute, value: -60 + bedDrift[i], to: midnight)!
            return Sleep(createdAt: iso.string(from: wake),
                         start: iso.string(from: onset),
                         end: iso.string(from: wake),
                         nap: false, scoreState: "SCORED",
                         score: .init(sleepConsistencyPercentage: consistency[i]))
        }
    }
}
