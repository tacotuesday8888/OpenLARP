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
            includePrivateEvidence: privacy.allowsPrivateEvidenceCloudSync,
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
    var goal: CloudCareerGoalDocument?
    var targetRoles: [CloudTargetRoleDocument]
    var proofRecords: [CloudProofRecordDocument]
    var outcomes: [CloudCareerOutcomeDocument]
    var readinessSnapshots: [CloudReadinessSnapshotDocument]
    var currentReadiness: ReadinessMetrics
    var policy: CloudExportPolicy

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case ownerUserID
        case generatedAt
        case userProfile
        case goal
        case targetRoles
        case proofRecords
        case outcomes
        case readinessSnapshots
        case currentReadiness
        case policy
    }

    init(
        ownerUserID: String,
        generatedAt: Date,
        userProfile: CloudUserProfileDocument? = nil,
        goal: CloudCareerGoalDocument? = nil,
        targetRoles: [CloudTargetRoleDocument] = [],
        proofRecords: [CloudProofRecordDocument] = [],
        outcomes: [CloudCareerOutcomeDocument] = [],
        readinessSnapshots: [CloudReadinessSnapshotDocument] = [],
        currentReadiness: ReadinessMetrics,
        policy: CloudExportPolicy,
        schemaVersion: Int = 2
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        ownerUserID = try container.decode(String.self, forKey: .ownerUserID)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        userProfile = try container.decodeIfPresent(CloudUserProfileDocument.self, forKey: .userProfile)
        targetRoles = try container.decodeIfPresent([CloudTargetRoleDocument].self, forKey: .targetRoles) ?? []
        proofRecords = try container.decodeIfPresent([CloudProofRecordDocument].self, forKey: .proofRecords) ?? []
        outcomes = try container.decodeIfPresent([CloudCareerOutcomeDocument].self, forKey: .outcomes) ?? []
        readinessSnapshots = try container.decodeIfPresent([CloudReadinessSnapshotDocument].self, forKey: .readinessSnapshots) ?? []
        currentReadiness = try container.decode(ReadinessMetrics.self, forKey: .currentReadiness)
        policy = try container.decode(CloudExportPolicy.self, forKey: .policy)

        do {
            goal = try container.decodeIfPresent(CloudCareerGoalDocument.self, forKey: .goal)
        } catch {
            if let legacyGoal = try? container.decodeIfPresent(CareerGoal.self, forKey: .goal) {
                goal = CloudCareerGoalDocument(
                    goal: legacyGoal,
                    ownerUserID: ownerUserID,
                    includePrivateEvidence: false
                )
            } else {
                throw error
            }
        }
    }
}

struct CloudCareerGoalPrivateContext: Codable, Equatable {
    var background: String
    var existingProof: String
    var confidence: Int
    var biggestBlocker: String
}

struct CloudCareerGoalDocument: Codable, Equatable {
    var schemaVersion: Int
    var ownerUserID: String
    var localID: String
    var currentStatus: CurrentStatus
    var targetRole: String
    var timeline: String
    var privateContext: CloudCareerGoalPrivateContext?
    var collectionPath: String
    var documentPath: String

    init(
        goal: CareerGoal,
        ownerUserID: String,
        includePrivateEvidence: Bool,
        localID: String = "current",
        schemaVersion: Int = 1
    ) {
        self.schemaVersion = schemaVersion
        self.ownerUserID = ownerUserID
        self.localID = localID
        currentStatus = goal.currentStatus
        targetRole = goal.targetRole
        timeline = goal.timeline
        privateContext = includePrivateEvidence
            ? CloudCareerGoalPrivateContext(
                background: goal.background,
                existingProof: goal.existingProof,
                confidence: goal.confidence,
                biggestBlocker: goal.biggestBlocker
            )
            : nil
        collectionPath = "users/\(ownerUserID)/goals"
        documentPath = "\(collectionPath)/\(localID)"
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
        accountID = nil
        email = nil
        displayName = profile.displayName
        segment = profile.segment
        backgroundSummary = ""
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

    private enum CodingKeys: String, CodingKey {
        case metadata
        case questID
        case questTitle
        case kind
        case text
        case link
        case submittedAt
        case quality
        case collectionPath
        case documentPath
    }

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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        metadata = try container.decode(CloudDocumentMetadata.self, forKey: .metadata)
        questID = try container.decode(String.self, forKey: .questID)
        questTitle = try container.decode(String.self, forKey: .questTitle)
        kind = try container.decode(ProofKind.self, forKey: .kind)
        text = try container.decode(String.self, forKey: .text)
        link = try container.decode(String.self, forKey: .link)
        attachments = []
        submittedAt = try container.decode(Date.self, forKey: .submittedAt)
        quality = try container.decodeIfPresent(QualityCheckResult.self, forKey: .quality)
        collectionPath = try container.decode(String.self, forKey: .collectionPath)
        documentPath = try container.decode(String.self, forKey: .documentPath)
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
    var uploadStatus: CareerGraphSyncUploadStatus
    var uploadReceipt: CareerGraphSyncUploadReceipt?
    var collectionPath: String
    var documentPath: String
    var localRelativePath: String

    private enum CodingKeys: String, CodingKey {
        case metadata
        case proofID
        case fileName
        case originalFileName
        case contentType
        case byteCount
        case createdAt
        case storagePath
        case uploadStatus
        case uploadReceipt
        case collectionPath
        case documentPath
    }

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
        uploadStatus = .pendingUpload
        uploadReceipt = nil
        collectionPath = "users/\(ownerUserID)/proofAttachments"
        documentPath = "\(collectionPath)/\(attachment.id.uuidString)"
        localRelativePath = attachment.localRelativePath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        metadata = try container.decode(CloudDocumentMetadata.self, forKey: .metadata)
        proofID = try container.decode(String.self, forKey: .proofID)
        fileName = try container.decode(String.self, forKey: .fileName)
        originalFileName = try container.decodeIfPresent(String.self, forKey: .originalFileName) ?? ""
        contentType = try container.decode(String.self, forKey: .contentType)
        byteCount = try container.decode(Int.self, forKey: .byteCount)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        storagePath = try container.decode(String.self, forKey: .storagePath)
        uploadStatus = try container.decodeIfPresent(CareerGraphSyncUploadStatus.self, forKey: .uploadStatus) ?? .pendingUpload
        uploadReceipt = try container.decodeIfPresent(CareerGraphSyncUploadReceipt.self, forKey: .uploadReceipt)
        collectionPath = try container.decode(String.self, forKey: .collectionPath)
        documentPath = try container.decode(String.self, forKey: .documentPath)
        localRelativePath = ""
    }

    func uploaded(with receipt: CareerGraphSyncUploadReceipt) -> CloudProofAttachmentDocument {
        var document = self
        document.uploadStatus = receipt.status
        document.uploadReceipt = receipt
        return document
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

extension CloudCareerGraphSnapshot {
    func applyingUploadReceipts(
        _ receipts: [CareerGraphSyncUploadReceipt]
    ) -> CloudCareerGraphSnapshot {
        guard !receipts.isEmpty else { return self }

        let receiptsByAttachmentID = Dictionary(uniqueKeysWithValues: receipts.map { ($0.attachmentID, $0) })
        var snapshot = self
        snapshot.proofRecords = snapshot.proofRecords.map { proof in
            var proof = proof
            proof.attachments = proof.attachments.map { attachment in
                guard let receipt = receiptsByAttachmentID[attachment.metadata.localID] else {
                    return attachment
                }
                return attachment.uploaded(with: receipt)
            }
            return proof
        }
        return snapshot
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
            goal: state.goal.map {
                CloudCareerGoalDocument(
                    goal: $0,
                    ownerUserID: ownerUserID,
                    includePrivateEvidence: policy.includePrivateEvidence
                )
            },
            targetRoles: state.targetRoles.map { CloudTargetRoleDocument(role: $0, ownerUserID: ownerUserID) },
            proofRecords: proofRecords,
            outcomes: outcomes,
            readinessSnapshots: readinessSnapshots,
            currentReadiness: state.progress.readiness,
            policy: policy
        )
    }
}
