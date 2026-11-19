import Foundation

enum MilestoneShareSelection {
    case streak
    case badge(Badge)
    case outcome(UUID)
}

struct MilestoneShareCard: Equatable {
    enum Kind {
        case streak, badge, outcome
    }

    static let filename = "openlarp-milestone.png"

    let kind: Kind
    let title: String
    let detail: String
    let systemImage: String

    var category: String {
        switch kind {
        case .streak: "Quest streak"
        case .badge: "OpenLARP badge"
        case .outcome: "Self-reported outcome"
        }
    }

    var caption: String { "\(category) · \(title). \(detail)" }

    init?(selection: MilestoneShareSelection, state: OpenLARPState) {
        guard state.userProfile?.privacy.shareWins == true else { return nil }

        switch selection {
        case .streak:
            let count = state.progress.streakCount
            guard count > 0 else { return nil }
            kind = .streak
            title = "\(count)-day streak"
            detail = "I’m building my streak one career quest at a time."
            systemImage = "flame.fill"

        case .badge(let badge):
            guard state.progress.badges.contains(badge) else { return nil }
            kind = .badge
            systemImage = "seal.fill"
            switch badge {
            case .firstGoal:
                title = "First goal set"
                detail = "I chose the career goal I want to work toward."
            case .firstProof:
                // A self-report or a partial-credit claim can earn this badge.
                title = "First quest entry"
                detail = "I recorded what I did for my first career quest."
            case .strongProof:
                // Older badges could be awarded without documented evidence inspection.
                guard state.progress.recentProof.contains(where: { proof in
                    proof.kind == .proof && proof.quality?.isAccepted == true &&
                        proof.quality?.inspectionScope.didInspectSubmittedEvidence == true
                }) else { return nil }
                title = "Strong proof"
                detail = "One of my quest submissions earned a badge for reviewed evidence."
            case .threeDayStreak, .weeklyStreak:
                title = badge.rawValue
                detail = "I earned this badge by keeping my career quest streak going."
            case .firstOutcome, .firstInterview, .firstOffer:
                // Badges persist after a user edits, hides, or deletes an outcome.
                guard state.outcomeLog.contains(where: { outcome in
                    guard !outcome.isPrivate, !outcome.isDeleted else { return false }
                    switch badge {
                    case .firstInterview: return outcome.kind == .interview
                    case .firstOffer: return outcome.kind == .offer
                    default: return outcome.kind != .rejection && outcome.kind != .changedGoal
                    }
                }) else { return nil }
                title = badge.rawValue
                detail = "I earned this badge for a self-reported career outcome."
            }

        case .outcome(let id):
            guard let outcome = state.outcomeLog.first(where: { $0.id == id }),
                  !outcome.isPrivate, !outcome.isDeleted else { return nil }
            kind = .outcome
            systemImage = outcome.kind.systemImage
            detail = "I added this update to my career log."
            title = switch outcome.kind {
            case .applied: "Application logged"
            case .interview: "Interview logged"
            case .rejection: "Rejection logged"
            case .offer: "Offer logged"
            case .changedGoal: "Goal change logged"
            case .other: "Career update logged"
            }
        }
    }
}
