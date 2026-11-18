import Foundation

enum FactorList {
    static let defaults = ["喝酒", "侧睡", "止鼾贴/鼻贴", "止鼾牙套", "鼻塞/感冒", "吃得晚", "很累", "抬高床头", "加湿器"]
    static let prefixes = ["鼾声记录·因素清单", "鼾聲記錄·因素清單", "Snore Log · Factor list"]
    static func encode(_ factors: [String]) throws -> String {
        let data = try JSONEncoder().encode(clean(factors))
        let payload = data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return L.t("鼾声记录·因素清单") + "\n" + payload
    }
    static func decode(_ text: String) throws -> [String] {
        guard text.utf8.count <= 32768, let prefix = prefixes.first(where: { text.contains($0) }), let range = text.range(of: prefix) else { throw StoreError.corrupt }
        var payload = text[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        payload = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload) else { throw StoreError.corrupt }
        let result = clean(try JSONDecoder().decode([String].self, from: data))
        guard !result.isEmpty else { throw StoreError.corrupt }; return result
    }
    static func clean(_ items: [String]) -> [String] {
        var seen: Set<String> = []
        return Array(items.compactMap { item -> String? in
            let value = String(item.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
            guard !value.isEmpty, seen.insert(value).inserted else { return nil }; return value
        }.prefix(50))
    }
}
