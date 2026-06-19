import Foundation

enum BackendAuthProvider: String, Codable, CaseIterable {
    case localMock
    case firebaseAuth
}

struct BackendIntegrationRoute: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, CaseIterable {
        case firebaseAuth
        case firestore
        case firebaseStorage
        case cloudFunctions
        case cloudRun
        case genkit

        var label: String {
            switch self {
            case .firebaseAuth: "Firebase Auth"
            case .firestore: "Firestore"
            case .firebaseStorage: "Firebase Storage"
            case .cloudFunctions: "Cloud Functions"
            case .cloudRun: "Cloud Run"
            case .genkit: "Genkit"
            }
        }
    }

    enum Status: String, Codable, CaseIterable {
        case notConnected
        case localMock
        case configured
        case connected
        case needsAuthentication
        case disabled
        case failed

        var label: String {
            switch self {
            case .notConnected: "Not connected"
            case .localMock: "Local mock"
            case .configured: "Configured"
            case .connected: "Connected"
            case .needsAuthentication: "Needs sign-in"
            case .disabled: "Disabled"
            case .failed: "Failed"
            }
        }
    }

    var kind: Kind
    var status: Status
    var displayName: String
    var detail: String?

    var id: String { kind.rawValue }

    init(
        kind: Kind,
        status: Status,
        displayName: String? = nil,
        detail: String? = nil
    ) {
        self.kind = kind
        self.status = status
        self.displayName = displayName ?? kind.label
        self.detail = detail
    }
}

typealias BackendIntegrationRouteKind = BackendIntegrationRoute.Kind
typealias BackendIntegrationRouteStatus = BackendIntegrationRoute.Status
typealias BackendIntegrationKind = BackendIntegrationRoute.Kind
typealias BackendIntegrationStatus = BackendIntegrationRoute.Status

enum BackendEventKind: String, Codable, CaseIterable, Identifiable {
    case goalConfirmed
    case questStarted
    case proofReviewed
    case proofClaimed
    case outcomeLogged
    case outcomeUpdated
    case outcomeDeleted
    case privacyUpdated
    case syncPreviewPrepared

    var id: String { rawValue }
}

enum BackendEventSyncStatus: String, Codable, CaseIterable {
    case pending
    case inFlight
    case acknowledged
    case failed
}

struct BackendEventSummary: Codable, Equatable {
    var targetRoleTitle: String?
    var questID: UUID?
    var questDay: Int?
    var proofID: UUID?
    var outcomeID: UUID?
    var outcomeKind: CareerOutcomeKind?
    var readinessOverall: Int?
    var xp: Int?
    var proofCount: Int?
    var qualityAccepted: Bool?
    var qualityScore: Int?
    var memoryMode: CareerMemoryMode?
    var shareWins: Bool?
    var allowsPrivateEvidenceCloudSync: Bool?
    var documentCount: Int?
    var proofUploadCount: Int?

    init(
        targetRoleTitle: String? = nil,
        questID: UUID? = nil,
        questDay: Int? = nil,
        proofID: UUID? = nil,
        outcomeID: UUID? = nil,
        outcomeKind: CareerOutcomeKind? = nil,
        readinessOverall: Int? = nil,
        xp: Int? = nil,
        proofCount: Int? = nil,
        qualityAccepted: Bool? = nil,
        qualityScore: Int? = nil,
        memoryMode: CareerMemoryMode? = nil,
        shareWins: Bool? = nil,
        allowsPrivateEvidenceCloudSync: Bool? = nil,
        documentCount: Int? = nil,
        proofUploadCount: Int? = nil
    ) {
        self.targetRoleTitle = Self.safeRoleTitle(targetRoleTitle)
        self.questID = questID
        self.questDay = questDay
        self.proofID = proofID
        self.outcomeID = outcomeID
        self.outcomeKind = outcomeKind
        self.readinessOverall = readinessOverall
        self.xp = xp
        self.proofCount = proofCount
        self.qualityAccepted = qualityAccepted
        self.qualityScore = qualityScore
        self.memoryMode = memoryMode
        self.shareWins = shareWins
        self.allowsPrivateEvidenceCloudSync = allowsPrivateEvidenceCloudSync
        self.documentCount = documentCount
        self.proofUploadCount = proofUploadCount
    }

    private enum CodingKeys: String, CodingKey {
        case targetRoleTitle
        case questID
        case questDay
        case proofID
        case outcomeID
        case outcomeKind
        case readinessOverall
        case xp
        case proofCount
        case qualityAccepted
        case qualityScore
        case memoryMode
        case shareWins
        case allowsPrivateEvidenceCloudSync
        case documentCount
        case proofUploadCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            targetRoleTitle: try container.decodeIfPresent(String.self, forKey: .targetRoleTitle),
            questID: try container.decodeIfPresent(UUID.self, forKey: .questID),
            questDay: try container.decodeIfPresent(Int.self, forKey: .questDay),
            proofID: try container.decodeIfPresent(UUID.self, forKey: .proofID),
            outcomeID: try container.decodeIfPresent(UUID.self, forKey: .outcomeID),
            outcomeKind: try container.decodeIfPresent(CareerOutcomeKind.self, forKey: .outcomeKind),
            readinessOverall: try container.decodeIfPresent(Int.self, forKey: .readinessOverall),
            xp: try container.decodeIfPresent(Int.self, forKey: .xp),
            proofCount: try container.decodeIfPresent(Int.self, forKey: .proofCount),
            qualityAccepted: try container.decodeIfPresent(Bool.self, forKey: .qualityAccepted),
            qualityScore: try container.decodeIfPresent(Int.self, forKey: .qualityScore),
            memoryMode: try container.decodeIfPresent(CareerMemoryMode.self, forKey: .memoryMode),
            shareWins: try container.decodeIfPresent(Bool.self, forKey: .shareWins),
            allowsPrivateEvidenceCloudSync: try container.decodeIfPresent(
                Bool.self,
                forKey: .allowsPrivateEvidenceCloudSync
            ),
            documentCount: try container.decodeIfPresent(Int.self, forKey: .documentCount),
            proofUploadCount: try container.decodeIfPresent(Int.self, forKey: .proofUploadCount)
        )
    }

    private static func safeRoleTitle(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        guard !trimmed.isEmpty else { return nil }
        guard !PrivacyFilter.looksSensitive(trimmed) else { return "career goal" }
        return String(trimmed.prefix(80))
    }
}

struct BackendEventRecord: Codable, Equatable, Identifiable {
    /// Caps acknowledged history only. Pending, in-flight, and failed records are durable outbox entries.
    static let maxStoredCount = 250
    static let safeSyncFailureSummary = "Backend event sync failed. Retry is safe because this event has an idempotency key."

    var id: UUID
    var schemaVersion: Int
    var kind: BackendEventKind
    var syncStatus: BackendEventSyncStatus
    var ownerUserID: String
    var entityID: String
    var idempotencyKey: String
    var occurredAt: Date
    var retryCount: Int
    var lastAttemptAt: Date?
    var failureSummary: String?
    var summary: BackendEventSummary

    init(
        id: UUID = UUID(),
        kind: BackendEventKind,
        syncStatus: BackendEventSyncStatus = .pending,
        ownerUserID: String,
        occurredAt: Date,
        entityID: String? = nil,
        retryCount: Int = 0,
        lastAttemptAt: Date? = nil,
        failureSummary: String? = nil,
        summary: BackendEventSummary = BackendEventSummary(),
        schemaVersion: Int = 1
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.syncStatus = syncStatus
        self.ownerUserID = ownerUserID
        self.entityID = entityID ?? id.uuidString
        idempotencyKey = Self.makeIdempotencyKey(
            ownerUserID: ownerUserID,
            kind: kind,
            entityID: self.entityID
        )
        self.occurredAt = Self.persistenceStableDate(occurredAt)
        self.retryCount = retryCount
        self.lastAttemptAt = lastAttemptAt.map(Self.persistenceStableDate)
        self.failureSummary = Self.safeFailureSummary(failureSummary)
        self.summary = summary
    }

    func isEligibleForSync(
        at timestamp: Date,
        retryDelay: TimeInterval,
        staleInFlightAge: TimeInterval
    ) -> Bool {
        switch syncStatus {
        case .pending:
            return true
        case .failed:
            guard let lastAttemptAt else { return true }
            return timestamp.timeIntervalSince(lastAttemptAt) >= retryDelay
        case .inFlight:
            guard let lastAttemptAt else { return true }
            return timestamp.timeIntervalSince(lastAttemptAt) >= staleInFlightAge
        case .acknowledged:
            return false
        }
    }

    mutating func markInFlight(at timestamp: Date) {
        syncStatus = .inFlight
        lastAttemptAt = Self.persistenceStableDate(timestamp)
        failureSummary = nil
    }

    mutating func markAcknowledged(at timestamp: Date) {
        syncStatus = .acknowledged
        lastAttemptAt = Self.persistenceStableDate(timestamp)
        failureSummary = nil
    }

    mutating func markFailed(at timestamp: Date) {
        syncStatus = .failed
        retryCount += 1
        lastAttemptAt = Self.persistenceStableDate(timestamp)
        failureSummary = Self.safeSyncFailureSummary
    }

    mutating func assignAuthenticatedOwnerIfLocal(_ authenticatedOwnerUserID: String) {
        guard ownerUserID.hasPrefix("local_"),
              ownerUserID != authenticatedOwnerUserID
        else { return }

        ownerUserID = authenticatedOwnerUserID
        idempotencyKey = Self.makeIdempotencyKey(
            ownerUserID: authenticatedOwnerUserID,
            kind: kind,
            entityID: entityID
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case schemaVersion
        case kind
        case syncStatus
        case ownerUserID
        case entityID
        case idempotencyKey
        case occurredAt
        case retryCount
        case lastAttemptAt
        case failureSummary
        case summary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        kind = try container.decode(BackendEventKind.self, forKey: .kind)
        syncStatus = try container.decodeIfPresent(BackendEventSyncStatus.self, forKey: .syncStatus) ?? .pending
        ownerUserID = try container.decode(String.self, forKey: .ownerUserID)
        let decodedIdempotencyKey = try container.decodeIfPresent(String.self, forKey: .idempotencyKey)
        entityID = try container.decodeIfPresent(String.self, forKey: .entityID) ??
            Self.legacyEntityID(
                from: decodedIdempotencyKey,
                ownerUserID: ownerUserID,
                kind: kind
            ) ??
            id.uuidString
        idempotencyKey = decodedIdempotencyKey ??
            Self.makeIdempotencyKey(ownerUserID: ownerUserID, kind: kind, entityID: entityID)
        occurredAt = Self.persistenceStableDate(try container.decode(Date.self, forKey: .occurredAt))
        retryCount = try container.decodeIfPresent(Int.self, forKey: .retryCount) ?? 0
        lastAttemptAt = try container.decodeIfPresent(Date.self, forKey: .lastAttemptAt).map(Self.persistenceStableDate)
        failureSummary = Self.safeFailureSummary(try container.decodeIfPresent(String.self, forKey: .failureSummary))
        summary = try container.decodeIfPresent(BackendEventSummary.self, forKey: .summary) ?? BackendEventSummary()
    }

    private static func makeIdempotencyKey(
        ownerUserID: String,
        kind: BackendEventKind,
        entityID: String
    ) -> String {
        "\(ownerUserID)-\(kind.rawValue)-\(entityID)"
    }

    private static func legacyEntityID(
        from idempotencyKey: String?,
        ownerUserID: String,
        kind: BackendEventKind
    ) -> String? {
        guard let idempotencyKey else { return nil }
        let prefix = "\(ownerUserID)-\(kind.rawValue)-"
        guard idempotencyKey.hasPrefix(prefix) else { return nil }
        let suffix = String(idempotencyKey.dropFirst(prefix.count))
        return suffix.isEmpty ? nil : suffix
    }

    private static func safeFailureSummary(_ value: String?) -> String? {
        guard value != nil else { return nil }
        return Self.safeSyncFailureSummary
    }

    private static func persistenceStableDate(_ date: Date) -> Date {
        Date(timeIntervalSince1970: floor(date.timeIntervalSince1970))
    }
}

struct LossyBackendEventRecordList: Decodable {
    var records: [BackendEventRecord]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var decodedRecords: [BackendEventRecord] = []

        while !container.isAtEnd {
            if let record = try? container.decode(BackendEventRecord.self) {
                decodedRecords.append(record)
            } else if (try? container.decode(DiscardedBackendEventRecord.self)) == nil {
                break
            }
        }

        records = decodedRecords
    }
}

private struct DiscardedBackendEventRecord: Decodable {}

private enum PrivacyFilter {
    static func looksSensitive(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        let blockedFragments = [
            "@",
            "http://",
            "https://",
            "www.",
            "/users/",
            "\\users\\",
            "api key",
            "apikey",
            "token",
            "secret",
            "password",
            "private",
            "sk-",
            "ghp_",
            "pk_live",
            "rk_live"
        ]
        if blockedFragments.contains(where: { lowercased.contains($0) }) {
            return true
        }

        if value.contains("/") || value.contains("\\") {
            return true
        }

        let domainFragments = [
            ".com",
            ".org",
            ".net",
            ".io",
            ".dev",
            ".edu",
            ".gov",
            ".ai",
            ".co"
        ]
        if domainFragments.contains(where: { lowercased.contains($0) }) {
            return true
        }

        if value.range(
            of: #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#,
            options: .regularExpression
        ) != nil {
            return true
        }

        if value.range(
            of: #"\.(pdf|png|jpe?g|txt|docx?|csv|json|md|swift|py|key|pem)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return true
        }

        return false
    }
}

struct BackendUserSession: Codable, Equatable {
    var ownerUserID: String
    var isAuthenticated: Bool
    var authProvider: BackendAuthProvider
    var accountID: String?
    var email: String?
    var auth: BackendIntegrationRoute
    var firestore: BackendIntegrationRoute
    var storage: BackendIntegrationRoute
    var functions: BackendIntegrationRoute
    var cloudRun: BackendIntegrationRoute
    var genkit: BackendIntegrationRoute
    var requiresUserApprovalForExternalActions: Bool

    var integrationRoutes: [BackendIntegrationRoute] {
        [
            auth,
            firestore,
            storage,
            functions,
            cloudRun,
            genkit
        ]
    }

    init(
        ownerUserID: String,
        isAuthenticated: Bool,
        authProvider: BackendAuthProvider,
        accountID: String? = nil,
        email: String? = nil,
        auth: BackendIntegrationRoute,
        firestore: BackendIntegrationRoute,
        storage: BackendIntegrationRoute,
        functions: BackendIntegrationRoute,
        cloudRun: BackendIntegrationRoute,
        genkit: BackendIntegrationRoute,
        requiresUserApprovalForExternalActions: Bool = true
    ) {
        self.ownerUserID = ownerUserID
        self.isAuthenticated = isAuthenticated
        self.authProvider = authProvider
        self.accountID = accountID
        self.email = email
        self.auth = auth
        self.firestore = firestore
        self.storage = storage
        self.functions = functions
        self.cloudRun = cloudRun
        self.genkit = genkit
        self.requiresUserApprovalForExternalActions = requiresUserApprovalForExternalActions
    }

    static func localOnly(for state: OpenLARPState) -> BackendUserSession {
        let localID = state.userProfile?.id.uuidString ?? "device"
        let privacy = state.userProfile?.privacy ?? .localDefault

        return BackendUserSession(
            ownerUserID: "local_\(localID)",
            isAuthenticated: false,
            authProvider: .localMock,
            accountID: nil,
            email: nil,
            auth: BackendIntegrationRoute(kind: .firebaseAuth, status: .notConnected),
            firestore: BackendIntegrationRoute(kind: .firestore, status: .notConnected),
            storage: BackendIntegrationRoute(kind: .firebaseStorage, status: .notConnected),
            functions: BackendIntegrationRoute(kind: .cloudFunctions, status: .notConnected),
            cloudRun: BackendIntegrationRoute(kind: .cloudRun, status: .notConnected),
            genkit: BackendIntegrationRoute(kind: .genkit, status: .localMock),
            requiresUserApprovalForExternalActions: privacy.requireApprovalForExternalActions
        )
    }

    static func firebaseAuthenticated(
        ownerUserID: String,
        accountID: String? = nil,
        email: String? = nil,
        requiresUserApprovalForExternalActions: Bool = true
    ) -> BackendUserSession {
        BackendUserSession(
            ownerUserID: ownerUserID,
            isAuthenticated: true,
            authProvider: .firebaseAuth,
            accountID: accountID,
            email: email,
            auth: BackendIntegrationRoute(kind: .firebaseAuth, status: .connected),
            firestore: BackendIntegrationRoute(kind: .firestore, status: .configured),
            storage: BackendIntegrationRoute(kind: .firebaseStorage, status: .configured),
            functions: BackendIntegrationRoute(kind: .cloudFunctions, status: .configured),
            cloudRun: BackendIntegrationRoute(kind: .cloudRun, status: .configured),
            genkit: BackendIntegrationRoute(kind: .genkit, status: .configured),
            requiresUserApprovalForExternalActions: requiresUserApprovalForExternalActions
        )
    }

    func redactedForCareerGraphSync() -> BackendUserSession {
        var session = self
        session.accountID = nil
        session.email = nil
        return session
    }

    func redactedForBackendEventSync() -> BackendUserSession {
        var session = self
        session.accountID = nil
        session.email = nil
        return session
    }
}

@MainActor
protocol BackendSessionProviding {
    func currentSession(for state: OpenLARPState) -> BackendUserSession
}

struct LocalMockBackendSessionProvider: BackendSessionProviding {
    init() {}

    func currentSession(for state: OpenLARPState) -> BackendUserSession {
        BackendUserSession.localOnly(for: state)
    }
}

struct BackendEventSyncRequest: Codable, Equatable {
    var schemaVersion: Int
    var requestedAt: Date
    var session: BackendUserSession
    var events: [BackendEventRecord]
    var integrationRoutes: [BackendIntegrationRoute]

    init(
        session: BackendUserSession,
        events: [BackendEventRecord],
        requestedAt: Date = Date(),
        schemaVersion: Int = 1
    ) {
        self.schemaVersion = schemaVersion
        self.requestedAt = requestedAt
        let syncSession = session.redactedForBackendEventSync()
        self.session = syncSession
        self.events = events
        integrationRoutes = syncSession.integrationRoutes
    }
}

struct BackendEventSyncReceipt: Codable, Equatable, Identifiable {
    var id: UUID { eventID }

    var schemaVersion: Int
    var eventID: UUID
    var idempotencyKey: String
    var status: BackendEventSyncStatus
    var acceptedAt: Date

    init(
        eventID: UUID,
        idempotencyKey: String,
        status: BackendEventSyncStatus,
        acceptedAt: Date,
        schemaVersion: Int = 1
    ) {
        self.schemaVersion = schemaVersion
        self.eventID = eventID
        self.idempotencyKey = idempotencyKey
        self.status = status
        self.acceptedAt = acceptedAt
    }
}

struct BackendEventSyncResult: Codable, Equatable {
    var schemaVersion: Int
    var requestedAt: Date
    var completedAt: Date
    var didContactNetwork: Bool
    var receipts: [BackendEventSyncReceipt]
    var integrationRoutes: [BackendIntegrationRoute]

    init(
        request: BackendEventSyncRequest,
        completedAt: Date? = nil,
        didContactNetwork: Bool = false,
        receipts: [BackendEventSyncReceipt],
        schemaVersion: Int = 1
    ) {
        self.schemaVersion = schemaVersion
        requestedAt = request.requestedAt
        self.completedAt = completedAt ?? request.requestedAt
        self.didContactNetwork = didContactNetwork
        self.receipts = receipts
        integrationRoutes = request.integrationRoutes
    }
}

@MainActor
protocol BackendEventSyncServicing {
    func syncEvents(_ request: BackendEventSyncRequest) async throws -> BackendEventSyncResult
}

struct LocalMockBackendEventSyncService: BackendEventSyncServicing {
    init() {}

    func syncEvents(_ request: BackendEventSyncRequest) async throws -> BackendEventSyncResult {
        BackendEventSyncResult(
            request: request,
            didContactNetwork: false,
            receipts: request.events.map {
                BackendEventSyncReceipt(
                    eventID: $0.id,
                    idempotencyKey: $0.idempotencyKey,
                    status: .acknowledged,
                    acceptedAt: request.requestedAt
                )
            }
        )
    }
}

enum PrivateEvidenceCloudSyncConsentStatus: String, Codable, Equatable {
    case accepted
    case revoked
}

struct PrivateEvidenceCloudSyncConsentRequest: Codable, Equatable {
    static let consentTextVersion = "private-evidence-cloud-sync-v1"

    var schemaVersion: Int
    var requestedAt: Date
    var session: BackendUserSession
    var enabled: Bool
    var consentTextVersion: String

    init(
        session: BackendUserSession,
        enabled: Bool,
        requestedAt: Date = Date(),
        consentTextVersion: String = Self.consentTextVersion,
        schemaVersion: Int = 1
    ) {
        self.schemaVersion = schemaVersion
        self.requestedAt = requestedAt
        self.session = session.redactedForBackendEventSync()
        self.enabled = enabled
        self.consentTextVersion = consentTextVersion
    }
}

struct PrivateEvidenceCloudSyncConsentResult: Codable, Equatable {
    var schemaVersion: Int
    var requestedAt: Date
    var completedAt: Date
    var didContactNetwork: Bool
    var status: PrivateEvidenceCloudSyncConsentStatus
    var allowsPrivateEvidenceCloudSync: Bool
    var firestoreDocumentPath: String?
    var consentTextVersion: String
    var externalActionTaken: Bool

    init(
        request: PrivateEvidenceCloudSyncConsentRequest,
        completedAt: Date? = nil,
        didContactNetwork: Bool = false,
        status: PrivateEvidenceCloudSyncConsentStatus,
        firestoreDocumentPath: String? = nil,
        externalActionTaken: Bool = false,
        schemaVersion: Int = 1
    ) {
        self.schemaVersion = schemaVersion
        requestedAt = request.requestedAt
        self.completedAt = completedAt ?? request.requestedAt
        self.didContactNetwork = didContactNetwork
        self.status = status
        allowsPrivateEvidenceCloudSync = status == .accepted
        self.firestoreDocumentPath = firestoreDocumentPath
        consentTextVersion = request.consentTextVersion
        self.externalActionTaken = externalActionTaken
    }
}

@MainActor
protocol PrivateEvidenceCloudSyncConsentServicing {
    func setConsent(_ request: PrivateEvidenceCloudSyncConsentRequest) async throws -> PrivateEvidenceCloudSyncConsentResult
}

struct LocalMockPrivateEvidenceCloudSyncConsentService: PrivateEvidenceCloudSyncConsentServicing {
    init() {}

    func setConsent(_ request: PrivateEvidenceCloudSyncConsentRequest) async throws -> PrivateEvidenceCloudSyncConsentResult {
        PrivateEvidenceCloudSyncConsentResult(
            request: request,
            didContactNetwork: false,
            status: request.enabled ? .accepted : .revoked,
            firestoreDocumentPath: nil
        )
    }
}

struct CareerGraphSyncPreparationRequest: Codable, Equatable {
    var schemaVersion: Int
    var requestedAt: Date
    var session: BackendUserSession
    var snapshot: CloudCareerGraphSnapshot
    var includePrivateEvidence: Bool
    var integrationRoutes: [BackendIntegrationRoute]

    var firestoreRootPath: String { "users/\(session.ownerUserID)" }

    init(
        state: OpenLARPState,
        session: BackendUserSession,
        requestedAt: Date = Date(),
        includePrivateEvidence: Bool? = nil,
        includeReadinessHistory: Bool = true,
        schemaVersion: Int = 1
    ) {
        let privacy = state.userProfile?.privacy ?? .localDefault
        let resolvedIncludePrivateEvidence = includePrivateEvidence ?? privacy.allowsPrivateEvidenceCloudSync
        let policy = CloudExportPolicy(
            ownerUserID: session.ownerUserID,
            includePrivateEvidence: resolvedIncludePrivateEvidence,
            includeReadinessHistory: includeReadinessHistory,
            allowsLongTermMemoryWrite: privacy.memoryMode == .cloudReady && session.isAuthenticated,
            requiresApprovalForExternalActions: session.requiresUserApprovalForExternalActions
        )

        self.schemaVersion = schemaVersion
        self.requestedAt = requestedAt
        let syncSession = session.redactedForCareerGraphSync()

        self.session = syncSession
        self.snapshot = LocalCareerGraphCloudMapper().makeSnapshot(
            from: state,
            policy: policy,
            generatedAt: requestedAt
        )
        self.includePrivateEvidence = resolvedIncludePrivateEvidence
        self.integrationRoutes = syncSession.integrationRoutes
    }
}

enum CareerGraphSyncStatus: String, Codable, CaseIterable {
    case preparedLocally
    case needsAuthentication
    case synced
    case failed

    var label: String {
        switch self {
        case .preparedLocally: "Prepared locally"
        case .needsAuthentication: "Needs sign-in"
        case .synced: "Synced"
        case .failed: "Failed"
        }
    }
}

struct CareerGraphSyncUploadIntent: Codable, Equatable, Identifiable {
    var id: String { attachmentID }

    var proofID: String
    var attachmentID: String
    var fileName: String
    var contentType: String
    var byteCount: Int
    var localRelativePath: String
    var storagePath: String
    var proofDocumentPath: String
    var attachmentDocumentPath: String
    var idempotencyKey: String

    private enum CodingKeys: String, CodingKey {
        case proofID
        case attachmentID
        case fileName
        case contentType
        case byteCount
        case storagePath
        case proofDocumentPath
        case attachmentDocumentPath
        case idempotencyKey
    }

    init(
        proofID: String,
        attachment: CloudProofAttachmentDocument
    ) {
        self.proofID = proofID
        attachmentID = attachment.metadata.localID
        fileName = attachment.fileName
        contentType = attachment.contentType
        byteCount = attachment.byteCount
        localRelativePath = attachment.localRelativePath
        storagePath = attachment.storagePath
        proofDocumentPath = "users/\(attachment.metadata.ownerUserID)/proofRecords/\(proofID)"
        attachmentDocumentPath = attachment.documentPath
        idempotencyKey = "\(attachment.metadata.ownerUserID)-\(attachment.metadata.localID)"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        proofID = try container.decode(String.self, forKey: .proofID)
        attachmentID = try container.decode(String.self, forKey: .attachmentID)
        fileName = try container.decode(String.self, forKey: .fileName)
        contentType = try container.decode(String.self, forKey: .contentType)
        byteCount = try container.decode(Int.self, forKey: .byteCount)
        localRelativePath = ""
        storagePath = try container.decode(String.self, forKey: .storagePath)
        proofDocumentPath = try container.decode(String.self, forKey: .proofDocumentPath)
        attachmentDocumentPath = try container.decode(String.self, forKey: .attachmentDocumentPath)
        idempotencyKey = try container.decode(String.self, forKey: .idempotencyKey)
    }
}

typealias CareerGraphUploadIntent = CareerGraphSyncUploadIntent

enum CareerGraphSyncUploadStatus: String, Codable, CaseIterable {
    case pendingUpload
    case uploaded
    case missingLocalFile
    case failed
}

struct CareerGraphSyncUploadReceipt: Codable, Equatable, Identifiable {
    var id: String { attachmentID }

    var schemaVersion: Int
    var proofID: String
    var attachmentID: String
    var storagePath: String
    var contentType: String
    var byteCount: Int
    var status: CareerGraphSyncUploadStatus
    var uploadedAt: Date?
    var storageBucket: String?
    var storageGeneration: Int64?
    var metadataGeneration: Int64?
    var md5Hash: String?
    var idempotencyKey: String

    init(
        intent: CareerGraphSyncUploadIntent,
        status: CareerGraphSyncUploadStatus,
        uploadedAt: Date? = nil,
        storageBucket: String? = nil,
        storageGeneration: Int64? = nil,
        metadataGeneration: Int64? = nil,
        md5Hash: String? = nil,
        schemaVersion: Int = 1
    ) {
        self.schemaVersion = schemaVersion
        proofID = intent.proofID
        attachmentID = intent.attachmentID
        storagePath = intent.storagePath
        contentType = intent.contentType
        byteCount = intent.byteCount
        self.status = status
        self.uploadedAt = uploadedAt
        self.storageBucket = storageBucket
        self.storageGeneration = storageGeneration
        self.metadataGeneration = metadataGeneration
        self.md5Hash = md5Hash
        idempotencyKey = intent.idempotencyKey
    }

    init?(
        existingObject metadata: CareerGraphStorageObjectMetadata,
        intent: CareerGraphSyncUploadIntent,
        session: BackendUserSession,
        uploadedAtFallback: Date? = nil
    ) {
        let expectedCustomMetadata = CareerGraphStorageObjectMetadata.expectedCustomMetadata(
            ownerUserID: session.ownerUserID,
            intent: intent
        )
        guard metadata.storagePath == intent.storagePath,
              metadata.contentType == intent.contentType,
              metadata.byteCount == intent.byteCount,
              metadata.customMetadata == expectedCustomMetadata
        else {
            return nil
        }

        self.init(
            intent: intent,
            status: .uploaded,
            uploadedAt: metadata.updatedAt ?? uploadedAtFallback,
            storageBucket: metadata.storageBucket,
            storageGeneration: metadata.storageGeneration,
            metadataGeneration: metadata.metadataGeneration,
            md5Hash: metadata.md5Hash
        )
    }
}

struct CareerGraphStorageObjectMetadata: Equatable, Sendable {
    static let allowedCustomMetadataKeys: Set<String> = [
        "ownerUserID",
        "proofID",
        "attachmentID",
        "idempotencyKey"
    ]

    var storagePath: String
    var contentType: String?
    var byteCount: Int
    var customMetadata: [String: String]
    var updatedAt: Date?
    var storageBucket: String?
    var storageGeneration: Int64?
    var metadataGeneration: Int64?
    var md5Hash: String?

    static func expectedCustomMetadata(
        ownerUserID: String,
        intent: CareerGraphSyncUploadIntent
    ) -> [String: String] {
        [
            "ownerUserID": ownerUserID,
            "proofID": intent.proofID,
            "attachmentID": intent.attachmentID,
            "idempotencyKey": intent.idempotencyKey
        ]
    }
}

enum CareerGraphProofAttachmentDataError: Error, Equatable {
    case missingLocalAttachment
    case byteCountMismatch
    case unsafeLocalPath
}

protocol CareerGraphProofAttachmentDataProviding: Sendable {
    func data(for uploadIntent: CareerGraphSyncUploadIntent) async throws -> Data
}

struct CareerGraphProofAttachmentUploadRequest: Sendable {
    var requestedAt: Date
    var session: BackendUserSession
    var uploadIntent: CareerGraphSyncUploadIntent
    var data: Data

    init(
        requestedAt: Date,
        session: BackendUserSession,
        uploadIntent: CareerGraphSyncUploadIntent,
        data: Data
    ) {
        self.requestedAt = requestedAt
        self.session = session.redactedForCareerGraphSync()
        self.uploadIntent = uploadIntent
        self.data = data
    }
}

protocol CareerGraphProofAttachmentUploading: Sendable {
    func upload(_ request: CareerGraphProofAttachmentUploadRequest) async throws -> CareerGraphSyncUploadReceipt
}

struct CareerGraphProofAttachmentPromotionRequest: Sendable {
    var requestedAt: Date
    var session: BackendUserSession
    var uploadIntent: CareerGraphSyncUploadIntent
    var uploadReceipt: CareerGraphSyncUploadReceipt

    init(
        requestedAt: Date,
        session: BackendUserSession,
        uploadIntent: CareerGraphSyncUploadIntent,
        uploadReceipt: CareerGraphSyncUploadReceipt
    ) {
        self.requestedAt = requestedAt
        self.session = session.redactedForCareerGraphSync()
        self.uploadIntent = uploadIntent
        self.uploadReceipt = uploadReceipt
    }
}

protocol CareerGraphProofAttachmentReceiptPromoting: Sendable {
    var writesProofAttachmentDocuments: Bool { get }

    func promote(_ request: CareerGraphProofAttachmentPromotionRequest) async throws -> CareerGraphSyncUploadReceipt
}

enum CareerGraphSyncDocumentType: String, Codable, CaseIterable {
    case profile
    case goal
    case targetRole
    case proofRecord
    case proofAttachment
    case outcome
    case readinessSnapshot
}

enum CareerGraphSyncOperation: String, Codable, CaseIterable {
    case upsert
}

struct CareerGraphSyncDocumentWrite: Codable, Equatable, Identifiable {
    var id: String { documentPath }

    var documentType: CareerGraphSyncDocumentType
    var operation: CareerGraphSyncOperation
    var collectionPath: String
    var documentPath: String

    init(
        documentType: CareerGraphSyncDocumentType,
        operation: CareerGraphSyncOperation = .upsert,
        collectionPath: String,
        documentPath: String
    ) {
        self.documentType = documentType
        self.operation = operation
        self.collectionPath = collectionPath
        self.documentPath = documentPath
    }
}

struct CareerGraphSyncManifest: Codable, Equatable {
    var schemaVersion: Int
    var ownerUserID: String
    var firestoreRootPath: String
    var generatedAt: Date
    var documentWrites: [CareerGraphSyncDocumentWrite]
    var storageUploads: [CareerGraphSyncUploadIntent]
    var requiredRoutes: [BackendIntegrationRoute]

    init(
        ownerUserID: String,
        firestoreRootPath: String,
        generatedAt: Date,
        documentWrites: [CareerGraphSyncDocumentWrite],
        storageUploads: [CareerGraphSyncUploadIntent],
        requiredRoutes: [BackendIntegrationRoute],
        schemaVersion: Int = 1
    ) {
        self.schemaVersion = schemaVersion
        self.ownerUserID = ownerUserID
        self.firestoreRootPath = firestoreRootPath
        self.generatedAt = generatedAt
        self.documentWrites = documentWrites
        self.storageUploads = storageUploads
        self.requiredRoutes = requiredRoutes
    }
}

struct CareerGraphSyncResult: Codable, Equatable {
    var schemaVersion: Int
    var status: CareerGraphSyncStatus
    var requestedAt: Date
    var preparedAt: Date
    var didContactNetwork: Bool
    var requiresAuthenticationToSync: Bool
    var firestoreRootPath: String
    var firestoreDocumentPaths: [String]
    var uploadIntents: [CareerGraphSyncUploadIntent]
    var uploadReceipts: [CareerGraphSyncUploadReceipt]
    var syncManifest: CareerGraphSyncManifest
    var integrationRoutes: [BackendIntegrationRoute]

    init(
        status: CareerGraphSyncStatus,
        request: CareerGraphSyncPreparationRequest,
        preparedAt: Date? = nil,
        didContactNetwork: Bool = false,
        requiresAuthenticationToSync: Bool? = nil,
        firestoreDocumentPaths: [String],
        uploadIntents: [CareerGraphSyncUploadIntent],
        uploadReceipts: [CareerGraphSyncUploadReceipt] = [],
        syncManifest: CareerGraphSyncManifest,
        schemaVersion: Int = 1
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        requestedAt = request.requestedAt
        self.preparedAt = preparedAt ?? request.requestedAt
        self.didContactNetwork = didContactNetwork
        self.requiresAuthenticationToSync = requiresAuthenticationToSync ?? !request.session.isAuthenticated
        firestoreRootPath = request.firestoreRootPath
        self.firestoreDocumentPaths = firestoreDocumentPaths
        self.uploadIntents = uploadIntents
        self.uploadReceipts = uploadReceipts
        self.syncManifest = syncManifest
        integrationRoutes = syncManifest.requiredRoutes
    }
}

struct CareerGraphSyncPreview: Codable, Equatable {
    var schemaVersion: Int
    var status: CareerGraphSyncStatus
    var requestedAt: Date
    var preparedAt: Date
    var documentCount: Int
    var proofUploadCount: Int
    var proofUploadedCount: Int
    var proofUploadByteCount: Int
    var includedPrivateEvidence: Bool
    var allowsLongTermMemoryWrite: Bool
    var didContactNetwork: Bool
    var requiresAuthenticationToSync: Bool
    var integrationRoutes: [BackendIntegrationRoute]

    init(
        status: CareerGraphSyncStatus,
        requestedAt: Date,
        preparedAt: Date,
        documentCount: Int,
        proofUploadCount: Int,
        proofUploadedCount: Int = 0,
        proofUploadByteCount: Int,
        includedPrivateEvidence: Bool,
        allowsLongTermMemoryWrite: Bool,
        didContactNetwork: Bool,
        requiresAuthenticationToSync: Bool,
        integrationRoutes: [BackendIntegrationRoute] = [],
        schemaVersion: Int = 1
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.requestedAt = requestedAt
        self.preparedAt = preparedAt
        self.documentCount = documentCount
        self.proofUploadCount = proofUploadCount
        self.proofUploadedCount = proofUploadedCount
        self.proofUploadByteCount = proofUploadByteCount
        self.includedPrivateEvidence = includedPrivateEvidence
        self.allowsLongTermMemoryWrite = allowsLongTermMemoryWrite
        self.didContactNetwork = didContactNetwork
        self.requiresAuthenticationToSync = requiresAuthenticationToSync
        self.integrationRoutes = integrationRoutes
    }

    init(request: CareerGraphSyncPreparationRequest, result: CareerGraphSyncResult) {
        self.init(
            status: result.status,
            requestedAt: result.requestedAt,
            preparedAt: result.preparedAt,
            documentCount: result.firestoreDocumentPaths.count,
            proofUploadCount: result.uploadIntents.count,
            proofUploadedCount: result.uploadReceipts.filter { $0.status == .uploaded }.count,
            proofUploadByteCount: result.uploadIntents.reduce(0) { $0 + $1.byteCount },
            includedPrivateEvidence: request.includePrivateEvidence,
            allowsLongTermMemoryWrite: request.snapshot.policy.allowsLongTermMemoryWrite,
            didContactNetwork: result.didContactNetwork,
            requiresAuthenticationToSync: result.requiresAuthenticationToSync,
            integrationRoutes: result.syncManifest.requiredRoutes
        )
    }
}

protocol CareerGraphSyncServicing: Sendable {
    func prepareSync(_ request: CareerGraphSyncPreparationRequest) async throws -> CareerGraphSyncResult
}

struct CareerGraphSyncPlanner: Sendable {
    init() {}

    func plan(_ request: CareerGraphSyncPreparationRequest) -> CareerGraphSyncManifest {
        let uploadIntents = uploadIntents(in: request.snapshot)
        return CareerGraphSyncManifest(
            ownerUserID: request.session.ownerUserID,
            firestoreRootPath: request.firestoreRootPath,
            generatedAt: request.requestedAt,
            documentWrites: documentWrites(in: request.snapshot),
            storageUploads: uploadIntents,
            requiredRoutes: requiredRoutes(
                from: request.integrationRoutes,
                needsStorage: !uploadIntents.isEmpty
            )
        )
    }

    func documentWrites(in snapshot: CloudCareerGraphSnapshot) -> [CareerGraphSyncDocumentWrite] {
        var writes: [CareerGraphSyncDocumentWrite] = []

        if let userProfile = snapshot.userProfile {
            writes.append(write(.profile, collectionPath: userProfile.collectionPath, documentPath: userProfile.documentPath))
        }
        if let goal = snapshot.goal {
            writes.append(write(.goal, collectionPath: goal.collectionPath, documentPath: goal.documentPath))
        }
        writes.append(contentsOf: snapshot.targetRoles.map {
            write(.targetRole, collectionPath: $0.collectionPath, documentPath: $0.documentPath)
        })
        for proof in snapshot.proofRecords {
            writes.append(write(.proofRecord, collectionPath: proof.collectionPath, documentPath: proof.documentPath))
            writes.append(contentsOf: proof.attachments.map {
                write(.proofAttachment, collectionPath: $0.collectionPath, documentPath: $0.documentPath)
            })
        }
        writes.append(contentsOf: snapshot.outcomes.map {
            write(.outcome, collectionPath: $0.collectionPath, documentPath: $0.documentPath)
        })
        writes.append(contentsOf: snapshot.readinessSnapshots.map {
            write(.readinessSnapshot, collectionPath: $0.collectionPath, documentPath: $0.documentPath)
        })

        var seen: Set<String> = []
        return writes.filter { seen.insert($0.documentPath).inserted }
    }

    func uploadIntents(in snapshot: CloudCareerGraphSnapshot) -> [CareerGraphSyncUploadIntent] {
        snapshot.proofRecords.flatMap { proof in
            proof.attachments.map { attachment in
                CareerGraphSyncUploadIntent(
                    proofID: proof.metadata.localID,
                    attachment: attachment
                )
            }
        }
    }

    private func requiredRoutes(
        from routes: [BackendIntegrationRoute],
        needsStorage: Bool
    ) -> [BackendIntegrationRoute] {
        let requiredKinds: [BackendIntegrationRoute.Kind] = needsStorage
            ? [.firebaseAuth, .firestore, .firebaseStorage]
            : [.firebaseAuth, .firestore]
        return requiredKinds.compactMap { kind in
            routes.first { $0.kind == kind }
        }
    }

    private func write(
        _ documentType: CareerGraphSyncDocumentType,
        collectionPath: String,
        documentPath: String
    ) -> CareerGraphSyncDocumentWrite {
        CareerGraphSyncDocumentWrite(
            documentType: documentType,
            collectionPath: collectionPath,
            documentPath: documentPath
        )
    }
}

struct LocalMockCareerGraphSyncService: CareerGraphSyncServicing {
    private let planner: CareerGraphSyncPlanner

    init(planner: CareerGraphSyncPlanner = CareerGraphSyncPlanner()) {
        self.planner = planner
    }

    func prepareSync(_ request: CareerGraphSyncPreparationRequest) async throws -> CareerGraphSyncResult {
        let manifest = planner.plan(request)

        return CareerGraphSyncResult(
            status: .preparedLocally,
            request: request,
            didContactNetwork: false,
            firestoreDocumentPaths: manifest.documentWrites.map(\.documentPath),
            uploadIntents: manifest.storageUploads,
            syncManifest: manifest
        )
    }
}
