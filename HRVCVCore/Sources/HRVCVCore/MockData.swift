import Foundation

// MARK: - Demo Data
// Run with HRVCV_MOCK=1 to use a built-in dataset instead of WHOOP — handy for
// demoing the app without an account and for UI work without burning API calls.
// Variants (for exercising each verdict): HRVCV_MOCK=ontrack | destabilizing.
public enum MockData {
    private static var variant: String { ProcessInfo.processInfo.environment["HRVCV_MOCK"] ?? "" }
    public static var isEnabled: Bool { !variant.isEmpty && variant != "0" }

    public static func records() -> [Recovery] {
        let hrv: [Double], recovery: [Int]
        switch variant {
        case "ontrack":
            // Steady around 45 ms with moderate spread: CV ~9%, on track.
            hrv      = [43, 46, 41, 47, 44, 48, 42,
                        40, 48, 42, 50, 44, 49, 41]
            recovery = [72, 78, 66, 80, 74, 82, 70,
                        68, 81, 70, 85, 75, 83, 69]
        case "destabilizing":
            // A tight ~51 ms week, then falling and swingy: CV ~17% with a
            // dropping baseline — the warning story.
            hrv      = [52, 50, 53, 51, 52, 50, 51,
                        50, 48, 38, 45, 30, 42, 35]
            recovery = [84, 80, 86, 82, 85, 81, 83,
                        70, 65, 44, 58, 30, 52, 40]
        default:
            // Two contrasting weeks: a tight ~34 ms baseline, then a step up to
            // a higher but swingier ~44 ms week — the "leveling up" story.
            hrv      = [35, 33, 36, 34, 35, 32, 34,
                        33.6, 34.8, 58.2, 48.7, 53.9, 41.7, 37.4]
            recovery = [66, 61, 68, 64, 65, 60, 63,
                        57, 58, 97, 93, 96, 71, 55]
        }
        let iso = ISO8601DateFormatter()
        return hrv.indices.map { i in
            let date = Calendar.current.date(byAdding: .day, value: i - (hrv.count - 1), to: Date())!
            return Recovery(cycleId: i,
                            createdAt: iso.string(from: date),
                            scoreState: "SCORED",
                            score: .init(recoveryScore: recovery[i], hrvRmssdMilli: hrv[i]))
        }
    }

    public static func sleepRecords() -> [Sleep] {
        let consistency: [Double]
        switch variant {
        case "ontrack":
            // Steady bed/wake timing, matching the steady HRV story.
            consistency = [82, 80, 85, 81, 83, 84, 82,
                           83, 81, 84, 82, 85, 83, 84]
        case "destabilizing":
            // Consistency erodes alongside the falling baseline — a plausible
            // "why" behind the destabilizing warning.
            consistency = [88, 86, 89, 87, 88, 86, 87,
                           80, 74, 62, 58, 45, 52, 48]
        default:
            // Consistency dips through the transition, then holds at a new
            // (still fine) level — same "leveling up" shape as the HRV story.
            consistency = [90, 88, 91, 89, 90, 87, 89,
                           85, 79, 68, 71, 74, 76, 78]
        }
        let iso = ISO8601DateFormatter()
        return consistency.indices.map { i in
            let date = Calendar.current.date(byAdding: .day, value: i - (consistency.count - 1), to: Date())!
            return Sleep(createdAt: iso.string(from: date), nap: false, scoreState: "SCORED",
                        score: .init(sleepConsistencyPercentage: consistency[i]))
        }
    }
}
