import Foundation

struct OpenLARPPersistence {
    let directory: URL
    let fileName: String

    var fileURL: URL {
        directory.appendingPathComponent(fileName)
    }

    init(directory: URL, fileName: String = "openlarp-state.json") {
        self.directory = directory
        self.fileName = fileName
    }

    static var live: OpenLARPPersistence {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return OpenLARPPersistence(directory: directory)
    }

    func load() throws -> OpenLARPState {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .empty
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(OpenLARPState.self, from: data)
    }

    func save(_ state: OpenLARPState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: [.atomic])
    }
}
