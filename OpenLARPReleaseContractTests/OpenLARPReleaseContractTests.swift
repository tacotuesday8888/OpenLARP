import Foundation
import XCTest
import OpenLARP

final class OpenLARPReleaseContractTests: XCTestCase {
    func testAppStoreReleaseContract() {
        XCTAssertEqual(Bundle.main.bundleURL.pathExtension, "app")
        XCTAssertNotEqual(Bundle(for: Self.self).bundleURL, Bundle.main.bundleURL)

        let snapshot = OpenLARPReleaseContractSnapshot.current()

        XCTAssertEqual(snapshot.bundleIdentifier, "com.openlarp.app")
        XCTAssertEqual(snapshot.bundledReleaseChannel, "app-store")
        XCTAssertEqual(snapshot.channel, "app-store")
        XCTAssertEqual(snapshot.accessMode, "free")
        XCTAssertEqual(snapshot.serviceMode, "local-only")
        XCTAssertEqual(snapshot.enabledCapabilities, [])
        XCTAssertFalse(snapshot.liveAIEnabled)
        XCTAssertEqual(snapshot.visibleTabs, ["today", "map", "progress", "profile"])
        XCTAssertEqual(
            snapshot.todaySections,
            ["header", "quest", "diagnostic", "progress", "outcome"]
        )
        XCTAssertEqual(
            snapshot.profileSections,
            [
                "hero",
                "careerSummary",
                "activeGoal",
                "recentOutcomes",
                "streak",
                "privacy",
                "badges",
                "proof",
                "rules"
            ]
        )
        XCTAssertEqual(snapshot.profilePrivacyPresentation, "localOnlyNotice")
        XCTAssertEqual(snapshot.activationOperations, ["refreshDailyAvailability"])
        XCTAssertEqual(snapshot.tabChangeOperations, ["refreshDailyAvailability"])
        XCTAssertNil(Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist"))
        XCTAssertNil(Bundle.main.url(forResource: "RevenueCat-Info", withExtension: "plist"))

        let privacyManifestURL = try! XCTUnwrap(
            Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy")
        )
        let privacyManifestData = try! Data(contentsOf: privacyManifestURL)
        let privacyManifest = try! XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: privacyManifestData,
                options: [],
                format: nil
            ) as? [String: Any]
        )
        XCTAssertEqual(privacyManifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual(privacyManifest["NSPrivacyTrackingDomains"] as? [String], [])
        XCTAssertEqual((privacyManifest["NSPrivacyCollectedDataTypes"] as? [Any])?.count, 0)
        XCTAssertEqual((privacyManifest["NSPrivacyAccessedAPITypes"] as? [Any])?.count, 0)

        let artifactPaths = FileManager.default
            .enumerator(
                at: Bundle.main.bundleURL,
                includingPropertiesForKeys: nil
            )?
            .compactMap { ($0 as? URL)?.lastPathComponent.lowercased() } ?? []
        let forbiddenServiceArtifactTokens = [
            "firebase",
            "googlesignin",
            "revenuecat",
            "purchases"
        ]
        let forbiddenServiceArtifacts = artifactPaths.filter { path in
            forbiddenServiceArtifactTokens.contains { path.contains($0) }
        }
        XCTAssertEqual(
            forbiddenServiceArtifacts,
            [],
            "The App Store app must not embed Firebase, Google Sign-In, or RevenueCat artifacts."
        )
    }
}
