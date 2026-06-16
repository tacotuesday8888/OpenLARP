import Foundation

struct CloudDocumentMetadata: Codable, Equatable {
    var schemaVersion: Int
    var ownerUserID: String
    var localID: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        ownerUserID: String,
        localID: UUID,
        createdAt: Date,
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
        schemaVersion: Int = 1
    ) {
        self.schemaVersion = schemaVersion
        self.ownerUserID = ownerUserID
        self.localID = localID.uuidString
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.deletedAt = deletedAt
    }
}

struct CloudExportPolicy: Codable, Equatable {
    var ownerUserID: String
    var includePrivateEvidence: Bool
    var includeReadinessHistory: Bool
    var allowsLongTermMemoryWrite: Bool
    var requiresApprovalForExternalActions: Bool

    init(
        ownerUserID: String,
        includePrivateEvidence: Bool = false,
        includeReadinessHistory: Bool = true,
        allowsLongTermMemoryWrite: Bool = false,
        requiresApprovalForExternalActions: Bool = true
    ) {
        self.ownerUserID = ownerUserID
        self.includePrivateEvidence = includePrivateEvidence
        self.includeReadinessHistory = includeReadinessHistory
        self.allowsLongTermMemoryWrite = allowsLongTermMemoryWrite
        self.requiresApprovalForExternalActions = requiresApprovalForExternalActions
    }

    init(ownerUserID: String, privacy: CareerUserPrivacySettings) {
        self.init(
            ownerUserID: ownerUserID,
            includePrivateEvidence: privacy.shareWins,
            includeReadinessHistory: true,
            allowsLongTermMemoryWrite: privacy.memoryMode == .cloudReady,
            requiresApprovalForExternalActions: privacy.requireApprovalForExternalActions
        )
    }
}

struct CloudCareerGraphSnapshot: Codable, Equatable {
    var schemaVersion: Int
    var ownerUserID: String
    var generatedAt: Date
    var userProfile: CloudUserProfileDocument?
    var goal: CareerGoal?
    var targetRoles: [CloudTargetRoleDocument]
    var proofRecords: [CloudProofRecordDocument]
    var outcomes: [CloudCareerOutcomeDocument]
    var readinessSnapshots: [CloudReadinessSnapshotDocument]
    var currentReadiness: ReadinessMetrics
    var policy: CloudExportPolicy

    init(
        ownerUserID: String,
        generatedAt: Date,
        userProfile: CloudUserProfileDocument? = nil,
        goal: CareerGoal? = nil,
        targetRoles: [CloudTargetRoleDocument] = [],
        proofRecords: [CloudProofRecordDocument] = [],
        outcomes: [CloudCareerOutcomeDocument] = [],
        readinessSnapshots: [CloudReadinessSnapshotDocument] = [],
        currentReadiness: ReadinessMetrics,
        policy: CloudExportPolicy,
        schemaVersion: Int = 1
    ) {
        self.schemaVersion = schemaVersion
        self.ownerUserID = ownerUserID
        self.generatedAt = generatedAt
        self.userProfile = userProfile
        self.goal = goal
        self.targetRoles = targetRoles
        self.proofRecords = proofRecords
        self.outcomes = outcomes
        self.readinessSnapshots = readinessSnapshots
        self.currentReadiness = currentReadiness
        self.policy = policy
    }
}

struct CloudUserProfileDocument: Codable, Equatable {
    var metadata: CloudDocumentMetadata
    var accountID: String?
    var email: String?
    var displayName: String
    var segment: CurrentStatus
    var backgroundSummary: String
    var minutesPerDay: Int
    var networkingComfort: Int
    var privacy: CareerUserPrivacySettings
    var collectionPath: String
    var documentPath: String

    init(profile: CareerUserProfile, ownerUserID: String) {
        metadata = CloudDocumentMetadata(
            ownerUserID: ownerUserID,
            localID: profile.id,
            createdAt: profile.createdAt,
            updatedAt: profile.updatedAt
        )
        accountID = profile.accountID
        email = profile.email
        displayName = profile.displayName
        segment = profile.segment
        backgroundSummary = profile.backgroundSummary
        minutesPerDay = profile.minutesPerDay
        networkingComfort = profile.networkingComfort
        privacy = profile.privacy
        collectionPath = "users/\(ownerUserID)/profiles"
        documentPath = "\(collectionPath)/\(profile.id.uuidString)"
    }
}

struct CloudTargetRoleDocument: Codable, Equatable {
    var metadata: CloudDocumentMetadata
    var title: String
    var seniority: TargetSeniority
    var roleFamily: RoleFamily
    var timeline: String
    var keywords: [String]
    var preferredLocations: [String]
    var status: TargetRoleStatus
    var collectionPath: String
    var documentPath: String

    init(role: TargetRole, ownerUserID: String) {
        metadata = CloudDocumentMetadata(
            ownerUserID: ownerUserID,
            localID: role.id,
            createdAt: role.createdAt,
            updatedAt: role.updatedAt
        )
        title = role.title
        seniority = role.seniority
        roleFamily = role.roleFamily
        timeline = role.timeline
        keywords = role.keywords
        preferredLocations = role.preferredLocations
        status = role.status
        collectionPath = "users/\(ownerUserID)/targetRoles"
        documentPath = "\(collectionPath)/\(role.id.uuidString)"
    }
}

struct CloudProofRecordDocument: Codable, Equatable {
    var metadata: CloudDocumentMetadata
    var questID: String
    var questTitle: String
    var kind: ProofKind
    var text: String
    var link: String
    var attachments: [CloudProofAttachmentDocument]
    var submittedAt: Date
    var quality: QualityCheckResult?
    var collectionPath: String
    var documentPath: String

    init(proof: ProofRecord, ownerUserID: String) {
        metadata = CloudDocumentMetadata(
            ownerUserID: ownerUserID,
            localID: proof.id,
            createdAt: proof.submittedAt,
            updatedAt: proof.submittedAt
        )
        questID = proof.questID.uuidString
        questTitle = proof.questTitle
        kind = proof.kind
        text = proof.text
        link = proof.link
        attachments = proof.attachments.map {
            CloudProofAttachmentDocument(attachment: $0, ownerUserID: ownerUserID, proofID: proof.id)
        }
        submittedAt = proof.submittedAt
        quality = proof.quality
        collectionPath = "users/\(ownerUserID)/proofRecords"
        documentPath = "\(collectionPath)/\(proof.id.uuidString)"
    }
}

struct CloudProofAttachmentDocument: Codable, Equatable {
    var metadata: CloudDocumentMetadata
    var proofID: String
    var fileName: String
    var originalFileName: String
    var contentType: String
    var byteCount: Int
    var createdAt: Date
    var storagePath: String
    var collectionPath: String
    var documentPath: String

    init(attachment: ProofAttachment, ownerUserID: String, proofID: UUID) {
        metadata = CloudDocumentMetadata(
            ownerUserID: ownerUserID,
            localID: attachment.id,
            createdAt: attachment.createdAt,
            updatedAt: attachment.createdAt
        )
        self.proofID = proofID.uuidString
        fileName = attachment.fileName
        originalFileName = attachment.originalFileName
        contentType = attachment.contentType
        byteCount = attachment.byteCount
        createdAt = attachment.createdAt
        storagePath = "users/\(ownerUserID)/proofAttachments/\(attachment.id.uuidString)"
        collectionPath = "users/\(ownerUserID)/proofAttachments"
        documentPath = "\(collectionPath)/\(attachment.id.uuidString)"
    }
}

struct CloudCareerOutcomeDocument: Codable, Equatable {
    var metadata: CloudDocumentMetadata
    var kind: CareerOutcomeKind
    var title: String
    var organizationName: String
    var note: String
    var occurredAt: Date
    var targetRoleID: String?
    var targetRoleTitle: String
    var relatedQuestID: String?
    var relatedProofID: String?
    var isPrivate: Bool
    var collectionPath: String
    var documentPath: String

    init(outcome: CareerOutcomeRecord, ownerUserID: String) {
        metadata = CloudDocumentMetadata(
            ownerUserID: ownerUserID,
            localID: outcome.id,
            createdAt: outcome.createdAt,
            updatedAt: outcome.updatedAt,
            deletedAt: outcome.deletedAt
        )
        kind = outcome.kind
        title = outcome.title
        organizationName = outcome.organizationName
        note = outcome.note
        occurredAt = outcome.occurredAt
        targetRoleID = outcome.targetRoleID?.uuidString
        targetRoleTitle = outcome.targetRoleTitle
        relatedQuestID = outcome.relatedQuestID?.uuidString
        relatedProofID = outcome.relatedProofID?.uuidString
        isPrivate = outcome.isPrivate
        collectionPath = "users/\(ownerUserID)/outcomes"
        documentPath = "\(collectionPath)/\(outcome.id.uuidString)"
    }
}

struct CloudReadinessSnapshotDocument: Codable, Equatable {
    var metadata: CloudDocumentMetadata
    var source: ReadinessSnapshotSource
    var reason: String
    var overall: Int
    var proofStrength: Int
    var confidence: Int
    var consistency: Int
    var skillProof: Int
    var networkStrength: Int
    var relatedQuestID: String?
    var relatedProofID: String?
    var relatedOutcomeID: String?
    var collectionPath: String
    var documentPath: String

    init(snapshot: ReadinessSnapshot, ownerUserID: String) {
        metadata = CloudDocumentMetadata(
            ownerUserID: ownerUserID,
            localID: snapshot.id,
            createdAt: snapshot.createdAt,
            updatedAt: snapshot.createdAt
        )
        source = snapshot.source
        reason = snapshot.reason
        overall = snapshot.overall
        proofStrength = snapshot.proofStrength
        confidence = snapshot.confidence
        consistency = snapshot.consistency
        skillProof = snapshot.skillProof
        networkStrength = snapshot.networkStrength
        relatedQuestID = snapshot.relatedQuestID?.uuidString
        relatedProofID = snapshot.relatedProofID?.uuidString
        relatedOutcomeID = snapshot.relatedOutcomeID?.uuidString
        collectionPath = "users/\(ownerUserID)/readinessSnapshots"
        documentPath = "\(collectionPath)/\(snapshot.id.uuidString)"
    }
}

protocol CareerGraphCloudMapping {
    func makeSnapshot(
        from state: OpenLARPState,
        policy: CloudExportPolicy,
        generatedAt: Date
    ) -> CloudCareerGraphSnapshot
}

struct LocalCareerGraphCloudMapper: CareerGraphCloudMapping {
    init() {}

    func makeSnapshot(
        from state: OpenLARPState,
        policy: CloudExportPolicy,
        generatedAt: Date = Date()
    ) -> CloudCareerGraphSnapshot {
        let ownerUserID = policy.ownerUserID
        let proofRecords = policy.includePrivateEvidence
            ? state.progress.recentProof.map { CloudProofRecordDocument(proof: $0, ownerUserID: ownerUserID) }
            : []
        let outcomes = state.outcomeLog
            .filter { !$0.isDeleted }
            .filter { policy.includePrivateEvidence || !$0.isPrivate }
            .map { CloudCareerOutcomeDocument(outcome: $0, ownerUserID: ownerUserID) }
        let readinessSnapshots = policy.includeReadinessHistory
            ? state.progress.readinessHistory.map {
                CloudReadinessSnapshotDocument(snapshot: $0, ownerUserID: ownerUserID)
            }
            : []

        return CloudCareerGraphSnapshot(
            ownerUserID: ownerUserID,
            generatedAt: generatedAt,
            userProfile: state.userProfile.map { CloudUserProfileDocument(profile: $0, ownerUserID: ownerUserID) },
            goal: state.goal,
            targetRoles: state.targetRoles.map { CloudTargetRoleDocument(role: $0, ownerUserID: ownerUserID) },
            proofRecords: proofRecords,
            outcomes: outcomes,
            readinessSnapshots: readinessSnapshots,
            currentReadiness: state.progress.readiness,
            policy: policy
        )
    }
}
