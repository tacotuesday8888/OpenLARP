import Foundation

enum OpenLARPPersistenceError: Error, Equatable {
    case ownerMismatch
    case unsupportedEnvelopeVersion(Int)
    case unsupportedStateSchema(Int)
    case unrecoverableState
}

enum OpenLARPPersistenceLoadSource: Equatable {
    case empty
    case primary
    case recoveredPrevious
}

struct OpenLARPPersistenceLoadResult: Equatable {
    let state: OpenLARPState
    let source: OpenLARPPersistenceLoadSource
}

private struct OpenLARPPersistedStateEnvelope: Codable {
    static let currentVersion = 1

    let envelopeVersion: Int
    let ownerKey: String
    let state: OpenLARPState
}

struct OpenLARPPersistence {
    let directory: URL
    let fileName: String
    let ownerKey: String?
    private let filePolicy: OpenLARPFilePolicy

    var fileURL: URL {
        directory.appendingPathComponent(fileName)
    }

    var previousFileURL: URL {
        let stem = (fileName as NSString).deletingPathExtension
        let fileExtension = (fileName as NSString).pathExtension
        let previousName = fileExtension.isEmpty
            ? "\(stem).previous"
            : "\(stem).previous.\(fileExtension)"
        return directory.appendingPathComponent(previousName)
    }

    init(
        directory: URL,
        fileName: String = "openlarp-state.json",
        ownerKey: String? = nil,
        filePolicy: OpenLARPFilePolicy = OpenLARPFilePolicy()
    ) {
        self.directory = directory
        self.fileName = fileName
        self.ownerKey = ownerKey
        self.filePolicy = filePolicy
    }

    static var live: OpenLARPPersistence {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return OpenLARPPersistence(directory: directory)
    }

    func load() throws -> OpenLARPState {
        try loadWithRecovery().state
    }

    func loadWithRecovery() throws -> OpenLARPPersistenceLoadResult {
        let fileManager = FileManager.default
        let hasPrimary = fileManager.fileExists(atPath: fileURL.path)
        let hasPrevious = fileManager.fileExists(atPath: previousFileURL.path)
        guard hasPrimary || hasPrevious else {
            return OpenLARPPersistenceLoadResult(state: .empty, source: .empty)
        }

        if hasPrimary {
            let primaryData = try Data(contentsOf: fileURL)
            do {
                return OpenLARPPersistenceLoadResult(
                    state: try decodeState(from: primaryData),
                    source: .primary
                )
            } catch let error as OpenLARPPersistenceError {
                switch error {
                case .ownerMismatch, .unsupportedEnvelopeVersion, .unsupportedStateSchema:
                    throw error
                case .unrecoverableState:
                    break
                }
            } catch {
                // A malformed primary may still be recoverable from the validated previous file.
            }
        }

        guard hasPrevious else {
            throw OpenLARPPersistenceError.unrecoverableState
        }
        let previousData = try Data(contentsOf: previousFileURL)
        do {
            let recovered = try decodeState(from: previousData)
            try filePolicy.write(previousData, to: fileURL, role: .state)
            return OpenLARPPersistenceLoadResult(
                state: recovered,
                source: .recoveredPrevious
            )
        } catch let error as OpenLARPPersistenceError {
            switch error {
            case .ownerMismatch, .unsupportedEnvelopeVersion, .unsupportedStateSchema:
                throw error
            case .unrecoverableState:
                throw OpenLARPPersistenceError.unrecoverableState
            }
        } catch {
            throw OpenLARPPersistenceError.unrecoverableState
        }
    }

    func save(_ state: OpenLARPState) throws {
        let data = try encodedState(state)
        _ = try decodeState(from: data)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            let currentData = try Data(contentsOf: fileURL)
            do {
                _ = try decodeState(from: currentData)
            } catch let error as OpenLARPPersistenceError {
                throw error
            } catch {
                throw OpenLARPPersistenceError.unrecoverableState
            }
            try filePolicy.write(currentData, to: previousFileURL, role: .previousState)
        }
        try filePolicy.write(data, to: fileURL, role: .state)
    }

    func erase() throws {
        for url in [fileURL, previousFileURL] where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func encodedState(_ state: OpenLARPState) throws -> Data {
        guard let ownerKey else {
            return try JSONEncoder.openLARPPersistence.encode(state)
        }
        return try JSONEncoder.openLARPPersistence.encode(
            OpenLARPPersistedStateEnvelope(
                envelopeVersion: OpenLARPPersistedStateEnvelope.currentVersion,
                ownerKey: ownerKey,
                state: state
            )
        )
    }

    private func decodeState(from data: Data) throws -> OpenLARPState {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw OpenLARPPersistenceError.unrecoverableState
        }

        if let expectedOwnerKey = ownerKey {
            let version = dictionary["envelopeVersion"] as? Int ?? 0
            guard version == OpenLARPPersistedStateEnvelope.currentVersion else {
                throw OpenLARPPersistenceError.unsupportedEnvelopeVersion(version)
            }
            guard dictionary["ownerKey"] as? String == expectedOwnerKey else {
                throw OpenLARPPersistenceError.ownerMismatch
            }
            guard let stateObject = dictionary["state"] as? [String: Any] else {
                throw OpenLARPPersistenceError.unrecoverableState
            }
            try validateStateSchema(in: stateObject)
            return try JSONDecoder.openLARPPersistence
                .decode(OpenLARPPersistedStateEnvelope.self, from: data)
                .state
        }

        try validateStateSchema(in: dictionary)
        return try JSONDecoder.openLARPPersistence.decode(OpenLARPState.self, from: data)
    }

    private func validateStateSchema(in dictionary: [String: Any]) throws {
        let schemaVersion = dictionary["schemaVersion"] as? Int ?? 1
        guard schemaVersion <= OpenLARPState.currentSchemaVersion else {
            throw OpenLARPPersistenceError.unsupportedStateSchema(schemaVersion)
        }
    }
}

extension JSONEncoder {
    static var openLARPPersistence: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var openLARPPersistence: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
