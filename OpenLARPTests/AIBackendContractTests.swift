import XCTest
@testable import OpenLARP

final class AIBackendContractTests: XCTestCase {
    func testRequestEnvelopeRedactsPrivateAndSessionIdentifiers() throws {
        let privateIdentifiers = V0AIBackendPrivateIdentifiers(
            ownerUserID: "owner-user-secret-123",
            accountID: "account-private-456",
            sessionID: "session-private-789",
            email: "langqi@example.com"
        )
        let envelope = makeEnvelope(privateIdentifiers: privateIdentifiers)

        let json = try encodedJSONString(envelope)

        XCTAssertFalse(json.contains("owner-user-secret-123"))
        XCTAssertFalse(json.contains("account-private-456"))
        XCTAssertFalse(json.contains("session-private-789"))
        XCTAssertFalse(json.contains("langqi@example.com"))
        XCTAssertFalse(json.contains("ownerUserID"))
        XCTAssertFalse(json.contains("accountID"))
        XCTAssertFalse(json.contains("sessionID"))
        XCTAssertFalse(json.contains("email"))
    }

    func testRequestEnvelopeCarriesProviderRouteOnlyWithoutDirectModelIDs() throws {
        let envelope = makeEnvelope(providerRoute: .cloudRunGenkit)

        let json = try encodedJSONString(envelope)

        XCTAssertTrue(json.contains(#""providerRoute" : "cloudRunGenkit""#))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("gemini"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("modelID"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("modelName"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("llm"))
    }

    func testRequestEnvelopeIncludesSafetyRules() throws {
        let envelope = makeEnvelope()

        XCTAssertEqual(envelope.safetyRules, .v0Default)
        XCTAssertTrue(envelope.safetyRules.hardBannedClaims.contains("fake employers"))
        XCTAssertTrue(envelope.safetyRules.hardBannedClaims.contains("fake certificates"))
        XCTAssertTrue(envelope.safetyRules.requiredBehaviors.contains("frame real experience honestly"))
        XCTAssertTrue(envelope.safetyRules.privacyRequirements.contains("do not take external actions without approval"))

        let json = try encodedJSONString(envelope)

        XCTAssertTrue(json.contains("hardBannedClaims"))
        XCTAssertTrue(json.contains("fake ownership claims"))
        XCTAssertTrue(json.contains("privacyRequirements"))
    }

    func testRequestEnvelopeEncodesAndDecodesStableJSON() throws {
        let envelope = makeEnvelope()
        let encoded = try encodedJSONString(envelope)

        XCTAssertEqual(encoded, stableEnvelopeJSON)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(
            V0AIBackendRequestEnvelope<SampleAIBackendPayload>.self,
            from: Data(encoded.utf8)
        )

        XCTAssertEqual(decoded, envelope)
        XCTAssertEqual(try encodedJSONString(decoded), stableEnvelopeJSON)
    }

    private func makeEnvelope(
        providerRoute: V0AIProviderRoute = .cloudRunGenkit,
        privateIdentifiers: V0AIBackendPrivateIdentifiers = .none
    ) -> V0AIBackendRequestEnvelope<SampleAIBackendPayload> {
        V0AIBackendRequestEnvelope(
            kind: .cookedDiagnostic,
            providerRoute: providerRoute,
            requestedAt: Date(timeIntervalSince1970: 0),
            requestID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            privacy: .localDefault,
            privateIdentifiers: privateIdentifiers,
            payload: SampleAIBackendPayload(promptPurpose: "diagnose", revision: 1)
        )
    }

    private func encodedJSONString<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private var stableEnvelopeJSON: String {
        """
        {
          "payload" : {
            "promptPurpose" : "diagnose",
            "revision" : 1
          },
          "run" : {
            "kind" : "cookedDiagnostic",
            "privacy" : {
              "allowsLongTermMemoryWrite" : false,
              "memoryMode" : "localOnly",
              "requiresUserApprovalForExternalActions" : true,
              "shareWins" : false
            },
            "providerRoute" : "cloudRunGenkit",
            "requestID" : "11111111-1111-1111-1111-111111111111",
            "requestedAt" : "1970-01-01T00:00:00Z",
            "schemaVersion" : 1
          },
          "safetyRules" : {
            "hardBannedClaims" : [
              "fake employers",
              "fake schools",
              "fake certificates",
              "fake job titles",
              "fake dates",
              "fake projects",
              "fake ownership claims"
            ],
            "privacyRequirements" : [
              "do not request provider credentials",
              "do not write long-term memory unless the user enabled it",
              "do not take external actions without approval"
            ],
            "requiredBehaviors" : [
              "frame real experience honestly",
              "separate proof from self-report",
              "recommend small truthful next steps"
            ]
          },
          "schemaVersion" : 1
        }
        """
    }
}

private struct SampleAIBackendPayload: Codable, Equatable {
    var promptPurpose: String
    var revision: Int
}
