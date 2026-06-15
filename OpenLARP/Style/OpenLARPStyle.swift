import SwiftUI

extension Color {
    static let openLARPBackground = Color(red: 0.95, green: 0.97, blue: 0.98)
    static let openLARPPanel = Color(red: 0.98, green: 0.99, blue: 1.00)
    static let openLARPPaper = Color.white
    static let openLARPInk = Color(red: 0.06, green: 0.13, blue: 0.20)
    static let openLARPSoftInk = Color(red: 0.40, green: 0.46, blue: 0.55)
    static let openLARPLine = Color(red: 0.86, green: 0.91, blue: 0.96)
    static let openLARPBlue = Color(red: 0.07, green: 0.46, blue: 1.00)
    static let openLARPBlueDark = Color(red: 0.03, green: 0.36, blue: 0.85)
    static let openLARPCyan = Color(red: 0.20, green: 0.79, blue: 1.00)
    static let openLARPGreen = Color(red: 0.11, green: 0.75, blue: 0.46)
    static let openLARPMint = Color(red: 0.13, green: 0.83, blue: 0.63)
    static let openLARPCoral = Color(red: 1.00, green: 0.31, blue: 0.43)
    static let openLARPYellow = Color(red: 1.00, green: 0.77, blue: 0.23)
    static let openLARPOrange = Color(red: 1.00, green: 0.54, blue: 0.24)
    static let openLARPPurple = Color(red: 0.46, green: 0.41, blue: 1.00)
    static let openLARPPink = Color(red: 1.00, green: 0.37, blue: 0.62)
    static let openLARPRed = Color(red: 1.00, green: 0.31, blue: 0.43)
    static let openLARPGray = Color(red: 0.54, green: 0.60, blue: 0.67)
}

struct Card<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.openLARPPaper)
            .overlay(
                RoundedRectangle(cornerRadius: 23, style: .continuous)
                    .stroke(Color.openLARPLine, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
            .shadow(color: Color(red: 0.79, green: 0.85, blue: 0.91), radius: 0, x: 0, y: 5)
    }
}

struct Pill: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.black))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(configuration.isPressed ? Color.openLARPBlueDark : Color.openLARPBlue)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color(red: 0.02, green: 0.27, blue: 0.66), radius: 0, x: 0, y: configuration.isPressed ? 2 : 6)
            .offset(y: configuration.isPressed ? 4 : 0)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .black, design: .rounded))
            .foregroundStyle(Color.openLARPBlueDark)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(configuration.isPressed ? Color(red: 0.82, green: 0.90, blue: 0.98) : Color(red: 0.92, green: 0.96, blue: 1.00))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color(red: 0.79, green: 0.85, blue: 0.91), radius: 0, x: 0, y: configuration.isPressed ? 2 : 5)
            .offset(y: configuration.isPressed ? 3 : 0)
    }
}

enum OpenLARPFeature {
    case path
    case quest
    case cooked
    case proof
    case stats
    case agent
    case recovery
    case profile
    case privacy

    var icon: String {
        switch self {
        case .path: "map.fill"
        case .quest: "bolt.fill"
        case .cooked: "flame.fill"
        case .proof: "doc.fill"
        case .stats: "chart.bar.fill"
        case .agent: "sparkles"
        case .recovery: "shield.fill"
        case .profile: "briefcase.fill"
        case .privacy: "lock.shield.fill"
        }
    }

    var colors: [Color] {
        switch self {
        case .path:
            [.openLARPCyan, .openLARPBlue]
        case .quest:
            [Color(red: 0.61, green: 0.55, blue: 1.00), .openLARPPurple]
        case .cooked:
            [Color(red: 1.00, green: 0.56, blue: 0.71), .openLARPCoral]
        case .proof:
            [.openLARPMint, .openLARPGreen]
        case .stats:
            [.openLARPYellow, .openLARPOrange]
        case .agent:
            [.openLARPCyan, .openLARPPurple]
        case .recovery:
            [Color(red: 0.55, green: 0.63, blue: 0.72), Color(red: 0.15, green: 0.23, blue: 0.35)]
        case .profile, .privacy:
            [Color(red: 0.37, green: 0.46, blue: 0.59), Color(red: 0.08, green: 0.15, blue: 0.24)]
        }
    }

    var accent: Color {
        switch self {
        case .path: .openLARPBlue
        case .quest: .openLARPPurple
        case .cooked: .openLARPCoral
        case .proof: .openLARPGreen
        case .stats: .openLARPOrange
        case .agent: .openLARPPurple
        case .recovery: Color(red: 0.15, green: 0.23, blue: 0.35)
        case .profile, .privacy: Color(red: 0.08, green: 0.15, blue: 0.24)
        }
    }

    var shadow: Color {
        switch self {
        case .path: .openLARPBlueDark
        case .quest: Color(red: 0.32, green: 0.26, blue: 0.79)
        case .cooked: Color(red: 0.72, green: 0.13, blue: 0.28)
        case .proof: Color(red: 0.05, green: 0.53, blue: 0.31)
        case .stats: Color(red: 0.71, green: 0.33, blue: 0.09)
        case .agent: Color(red: 0.22, green: 0.25, blue: 0.74)
        case .recovery: Color(red: 0.08, green: 0.15, blue: 0.24)
        case .profile, .privacy: Color(red: 0.04, green: 0.06, blue: 0.12)
        }
    }
}

struct FeatureMark: View {
    let feature: OpenLARPFeature
    var size: CGFloat = 38

    var body: some View {
        ZStack {
            LinearGradient(colors: feature.colors, startPoint: .top, endPoint: .bottom)

            Circle()
                .fill(.white.opacity(0.30))
                .frame(width: size * 0.46, height: size * 0.46)
                .offset(x: size * 0.38, y: -size * 0.38)

            Image(systemName: feature.icon)
                .font(.system(size: size * 0.50, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size >= 38 ? 15 : 13, style: .continuous))
        .shadow(color: feature.shadow.opacity(0.72), radius: 0, x: 0, y: size >= 38 ? 5 : 4)
        .accessibilityHidden(true)
    }
}

struct OpenLARPHeroCard: View {
    let feature: OpenLARPFeature
    let eyebrow: String
    let title: String
    let subtitle: String
    let stat: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                FeatureMark(feature: feature, size: 42)

                VStack(alignment: .leading, spacing: 4) {
                    Text(eyebrow.uppercased())
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)

                    Text(title)
                        .font(.system(size: 27, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                }

                Spacer(minLength: 8)

                Text(stat)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(minWidth: 45, minHeight: 29)
                    .padding(.horizontal, 9)
                    .background(.white.opacity(0.18))
                    .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 1))
                    .clipShape(Capsule())
            }

            Text(subtitle)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: feature.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: feature.shadow.opacity(0.34), radius: 0, x: 0, y: 8)
    }
}

struct SectionHeader: View {
    let feature: OpenLARPFeature
    let eyebrow: String
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            FeatureMark(feature: feature, size: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow.uppercased())
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(feature.accent)
                    .lineLimit(1)

                Text(title)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(Color.openLARPInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SummaryTile: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            Text(label)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(Color.openLARPInk)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background(color.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(color.opacity(0.28), lineWidth: 2))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

struct SprintStrip: View {
    let completed: Int
    let total: Int

    init(completed: Int, total: Int = 7) {
        self.completed = completed
        self.total = max(total, 1)
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { index in
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(fill(for: index))
                    .frame(height: 22)
                    .accessibilityLabel("Quest day \(index + 1)")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(min(max(completed, 0), total)) of \(total) sprint days complete")
    }

    private func fill(for index: Int) -> LinearGradient {
        if index < completed {
            return LinearGradient(colors: [.openLARPMint, .openLARPGreen], startPoint: .top, endPoint: .bottom)
        } else if index == completed {
            return LinearGradient(colors: [.openLARPYellow, .openLARPOrange], startPoint: .top, endPoint: .bottom)
        } else {
            return LinearGradient(colors: [Color(red: 0.92, green: 0.95, blue: 0.98), Color(red: 0.92, green: 0.95, blue: 0.98)], startPoint: .top, endPoint: .bottom)
        }
    }
}

struct ReadinessRings: View {
    let value: Int

    var body: some View {
        let progress = CGFloat(min(max(value, 0), 100)) / 100

        ZStack {
            Circle()
                .stroke(Color(red: 0.90, green: 0.94, blue: 0.97), lineWidth: 18)

            Circle()
                .trim(from: 0, to: max(progress, 0.06))
                .stroke(
                    AngularGradient(colors: [.openLARPOrange, .openLARPPurple, .openLARPBlue], center: .center),
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Circle()
                .stroke(Color(red: 0.90, green: 0.94, blue: 0.97), lineWidth: 12)
                .frame(width: 94, height: 94)

            Circle()
                .trim(from: 0, to: min(max(progress + 0.14, 0.08), 1))
                .stroke(
                    AngularGradient(colors: [.openLARPGreen, .openLARPMint], center: .center),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .frame(width: 94, height: 94)
                .rotationEffect(.degrees(-90))

            Text("\(value)")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(Color.openLARPBlueDark)
        }
        .frame(width: 142, height: 142)
        .accessibilityLabel("Readiness \(value) percent")
    }
}
