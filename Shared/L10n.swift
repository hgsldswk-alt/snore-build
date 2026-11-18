import Foundation

enum L {
    static func t(_ key: String) -> String { NSLocalizedString(key, comment: "") }
    static func f(_ key: String, _ args: CVarArg...) -> String { String(format: t(key), locale: Locale.current, arguments: args) }
    static func date(_ date: Date, weekday: Bool = false) -> String {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate(weekday ? "MMM d EEEE" : "MMM d"); return f.string(from: date)
    }
    static func clock(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: date)
    }
    static func duration(_ seconds: Double) -> String {
        let s = max(0, Int(seconds)); return String(format: "%02d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
    }
}
