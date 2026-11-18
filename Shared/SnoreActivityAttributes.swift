import ActivityKit
import AppIntents
import Foundation

struct SnoreActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable { var snoreCount: Int }
    var startedAt: Date
    var nightID: String
}

enum RecordingActions {
    @MainActor static var stop: ((String) -> Void)?
}
struct StopRecordingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "结束"
    static var openAppWhenRun: Bool = false
    @Parameter(title: "记录") var nightID: String

    init() {}
    init(nightID: String) { self.nightID = nightID }

    @MainActor func perform() async throws -> some IntentResult {
        RecordingActions.stop?(nightID)
        return .result()
    }
}
