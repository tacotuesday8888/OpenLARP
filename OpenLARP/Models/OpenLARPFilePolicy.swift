import Foundation

enum OpenLARPFileRole: Sendable {
    case state
    case previousState
    case ownerMetadata
    case committedProof
    case proofDraft
    case cache
    case migrationMetadata
    case temporaryExport

    var isExcludedFromBackup: Bool {
        switch self {
        case .state, .previousState, .ownerMetadata, .committedProof:
            false
        case .proofDraft, .cache, .migrationMetadata, .temporaryExport:
            true
        }
    }
}

struct OpenLARPFilePolicy: Sendable {
    let fileProtectionType = FileProtectionType.complete

    func createDirectory(at url: URL, role: OpenLARPFileRole) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: fileProtectionType]
        )
        try apply(to: url, role: role)
    }

    func write(_ data: Data, to url: URL, role: OpenLARPFileRole) throws {
        try createDirectory(at: url.deletingLastPathComponent(), role: role)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        try apply(to: url, role: role)
    }

    func apply(to url: URL, role: OpenLARPFileRole) throws {
        try FileManager.default.setAttributes(
            [.protectionKey: fileProtectionType],
            ofItemAtPath: url.path
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = role.isExcludedFromBackup
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }
}
