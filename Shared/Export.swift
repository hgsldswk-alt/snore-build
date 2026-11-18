import Foundation

enum Export {
    static func csv(_ nights: [Night]) -> String {
        func quote(_ value: String) -> String {
            var s = value
            if let first = s.first, "=+-@".contains(first) { s = "'" + s }
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let f = ISO8601DateFormatter()
        var rows = ["day,start,end,score,recorded_seconds,snore_seconds,interrupted_seconds,factors,end_reason"]
        for n in nights.sorted(by: { $0.startedAt < $1.startedAt }) {
            let values = [n.dayKey, f.string(from: n.startedAt), f.string(from: n.endDate), n.score.map(String.init) ?? "", String(n.recordedSeconds), String(n.adjustedSnoreSeconds), String(n.interruptedSeconds), n.factors.sorted().map { L.t($0) }.joined(separator: " / "), n.endReason.rawValue]
            rows.append(values.map(quote).joined(separator: ","))
        }
        return "\u{feff}" + rows.joined(separator: "\r\n")
    }
    static func make(_ data: AppData, store: Store) throws -> [URL] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SnoreLog-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var completed = false
        defer { if !completed { try? FileManager.default.removeItem(at: folder) } }
        let csvURL = folder.appendingPathComponent("SnoreLog.csv"); try csv(data.nights).write(to: csvURL, atomically: true, encoding: .utf8)
        var files: [(String, URL)] = []
        let nights = data.nights.filter { !$0.inProgress }
        for n in nights {
            for clip in n.clips + n.talkClips {
                let url = store.clipURL(nightID: n.id, fileName: clip.fileName)
                if FileManager.default.fileExists(atPath: url.path) { files.append(("Clips/" + n.id.uuidString + "/" + url.lastPathComponent, url)) }
            }
            for segment in n.fullSegments {
                let url = store.fullURL(segment.fileName)
                if FileManager.default.fileExists(atPath: url.path) {
                    files.append(("Full/" + url.lastPathComponent, url))
                }
            }
        }
        let json = folder.appendingPathComponent("records.json"); try JSONEncoder().encode(nights).write(to: json)
        files.append(("records.json", json))
        let zip = folder.appendingPathComponent("SnoreLog-clips.zip"); try StoredZIP.write(files, to: zip)
        completed = true
        return [csvURL, zip]
    }
}

enum StoredZIP {
    private static func append<T: FixedWidthInteger>(_ n: T, to data: inout Data) {
        var value = n.littleEndian; withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }
    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data { crc ^= UInt32(byte); for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0) } }
        return crc ^ 0xffffffff
    }
    static func write(_ files: [(String, URL)], to url: URL) throws {
        guard files.count <= Int(UInt16.max) else { throw StoreError.corrupt }
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let out = try FileHandle(forWritingTo: url); defer { try? out.close() }
        var central = Data(); var offset: UInt32 = 0
        for (name, path) in files {
            let bytes = try Data(contentsOf: path, options: .mappedIfSafe); let filename = Data(name.utf8)
            guard bytes.count < Int(UInt32.max), filename.count < Int(UInt16.max) else { throw StoreError.corrupt }
            let size = UInt32(bytes.count); let crc = crc32(bytes); var header = Data()
            append(UInt32(0x04034b50), to: &header); append(UInt16(20), to: &header); append(UInt16(0x800), to: &header)
            append(UInt16(0), to: &header); append(UInt16(0), to: &header); append(UInt16(0x21), to: &header)
            append(crc, to: &header); append(size, to: &header); append(size, to: &header)
            append(UInt16(filename.count), to: &header); append(UInt16(0), to: &header); header.append(filename)
            try out.write(contentsOf: header); try out.write(contentsOf: bytes)
            var record = Data(); append(UInt32(0x02014b50), to: &record)
            append(UInt16(20), to: &record); append(UInt16(20), to: &record); append(UInt16(0x800), to: &record)
            append(UInt16(0), to: &record); append(UInt16(0), to: &record); append(UInt16(0x21), to: &record)
            append(crc, to: &record); append(size, to: &record); append(size, to: &record)
            append(UInt16(filename.count), to: &record)
            for _ in 0..<4 { append(UInt16(0), to: &record) }
            append(UInt32(0), to: &record); append(offset, to: &record); record.append(filename); central.append(record)
            let next = UInt64(offset) + UInt64(header.count) + UInt64(bytes.count)
            guard next < UInt64(UInt32.max) else { throw StoreError.corrupt }; offset = UInt32(next)
        }
        try out.write(contentsOf: central); var end = Data(); append(UInt32(0x06054b50), to: &end)
        append(UInt16(0), to: &end); append(UInt16(0), to: &end)
        append(UInt16(files.count), to: &end); append(UInt16(files.count), to: &end)
        append(UInt32(central.count), to: &end); append(offset, to: &end); append(UInt16(0), to: &end)
        try out.write(contentsOf: end)
    }
}
