import Foundation

enum Launch {
    static let freePeriod = false

    static var isFree: Bool { freePeriod && !has("-paid-mode") && !has("-paywall") && !has("-expired") }

    static func has(_ flag: String) -> Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains(flag)
        #else
        return false
        #endif
    }

    static var isolated: Bool {
        ["-demo-night", "-uitest-fresh", "-ui-testing", "-recording", "-night", "-history", "-factors",
         "-settings", "-share", "-recovered", "-mic-denied", "-paywall", "-expired"].contains(where: has)
    }

    static var fakeAudio: Bool { isolated }
}
