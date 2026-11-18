import Foundation

enum ShareText {
    static var storeURL: URL? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "APP_STORE_ID") as? String,
              !id.isEmpty, id.allSatisfy(\.isNumber) else { return nil }
        return URL(string: "https://apps.apple.com/app/id" + id)
    }
    static func text(_ night: Night) -> String {
        let score = night.score.map(String.init) ?? "–"
        return L.f("昨晚的鼾声分数：%@。录音只在自己手机上。", score) + "\n" + L.t("#打呼噜 #睡眠 #止鼾") + (storeURL.map { "\n" + $0.absoluteString } ?? "")
    }
}
