import Foundation

enum DateFormatting {
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatterNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let hhmm: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static let hhmmss: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private static let hhmmssSSS: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private static let fullFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    // MARK: - Parse

    static func parseISO(_ string: String) -> Date? {
        isoFormatter.date(from: string) ?? isoFormatterNoFrac.date(from: string)
    }

    /// True if the source ISO string carries sub-second precision.
    /// We inspect the raw string rather than the Date because Date always
    /// stores sub-second precision — we want to know what the source had.
    static func hasFractionalSeconds(_ isoString: String) -> Bool {
        isoString.contains(".") && isoString.range(of: #"\.\d"#, options: .regularExpression) != nil
    }

    // MARK: - Time display

    /// Short time — HH:mm.
    static func timeString(_ date: Date) -> String {
        hhmm.string(from: date)
    }

    /// Precise time — HH:mm:ss.SSS when the source had millisecond precision,
    /// HH:mm:ss otherwise.
    static func preciseTimeString(_ date: Date, sourceISO: String? = nil) -> String {
        if let iso = sourceISO, hasFractionalSeconds(iso) {
            return hhmmssSSS.string(from: date)
        }
        return hhmmss.string(from: date)
    }

    // MARK: - Date display

    static func dateString(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return hhmm.string(from: date)
        } else if cal.isDate(date, equalTo: Date(), toGranularity: .year) {
            return dateFormatter.string(from: date)
        } else {
            return fullFormatter.string(from: date)
        }
    }

    // MARK: - Duration display

    static func durationString(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "\(Int(interval))s"
        }
    }
}
