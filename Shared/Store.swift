import Foundation

enum StoreError: Error { case corrupt, unsupportedVersion, missingGroup }
struct Store {
    let root: URL
    var url: URL { root.appendingPathComponent("snorelog.json") }
    init(root: URL? = nil) {
        if let root = root { self.root = root; return }
        let group = Bundle.main.object(forInfoDictionaryKey: "SnoreLogAppGroup") as? String ?? "group.com.hgsldswk.snore"
        self.root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SnoreLog")
    }
    func load() throws -> AppData {
        guard FileManager.default.fileExists(atPath: url.path) else { return AppData() }
        return try JSONDecoder().decode(AppData.self, from: Data(contentsOf: url))
    }
    func prepare() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
    }
    func save(_ data: AppData) throws {
        try prepare()
        try JSONEncoder().encode(data).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func clipURL(nightID: UUID, fileName: String) -> URL {
        root.appendingPathComponent("Clips").appendingPathComponent(nightID.uuidString).appendingPathComponent(URL(fileURLWithPath: fileName).lastPathComponent)
    }
    func fullURL(_ fileName: String) -> URL { root.appendingPathComponent("Full").appendingPathComponent(URL(fileURLWithPath: fileName).lastPathComponent) }
    func removeClip(_ clip: Clip, nightID: UUID) throws {
        let path = clipURL(nightID: nightID, fileName: clip.fileName)
        if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
    }
    func fullBytes() -> Int64 {
        let folder = root.appendingPathComponent("Full")
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
    func cleanFull(_ data: inout AppData, now: Date = Date(), all: Bool = false) throws {
        for i in data.nights.indices where !data.nights[i].inProgress {
            guard all || now.timeIntervalSince(data.nights[i].endDate) >= 14 * 86400 else { continue }
            let files = data.nights[i].fullSegments.map(\.fileName)
            for file in files {
                let path = fullURL(file)
                if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
            }
            data.nights[i].fullAudioFile = nil
            data.nights[i].audioSegments = []
        }
    }

    func discardUnreferencedAudio(in data: AppData) {
        let files = data.nights.flatMap { night in
            (night.clips + night.talkClips).map { clipURL(nightID: night.id, fileName: $0.fileName) }
                + night.fullSegments.map { fullURL($0.fileName) }
        }
        let keep = Set(files.map { $0.standardizedFileURL.path })
        for folder in ["Clips", "Full"] {
            let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
            let contents = FileManager.default.enumerator(at: root.appendingPathComponent(folder),
                includingPropertiesForKeys: [.isRegularFileKey], options: options)
            while let file = contents?.nextObject() as? URL {
                if file.pathExtension == "m4a", !keep.contains(file.standardizedFileURL.path) {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
    }
}
