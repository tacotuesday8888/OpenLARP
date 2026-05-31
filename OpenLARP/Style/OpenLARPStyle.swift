import SwiftUI

extension Color {
    static let openLARPBackground = Color(red: 0.97, green: 0.98, blue: 0.95)
    static let openLARPInk = Color(red: 0.10, green: 0.12, blue: 0.11)
    static let openLARPSoftInk = Color(red: 0.35, green: 0.38, blue: 0.35)
    static let openLARPGreen = Color(red: 0.16, green: 0.62, blue: 0.34)
    static let openLARPCoral = Color(red: 0.91, green: 0.32, blue: 0.23)
    static let openLARPYellow = Color(red: 0.95, green: 0.72, blue: 0.20)
    static let openLARPRed = Color(red: 0.76, green: 0.18, blue: 0.22)
    static let openLARPGray = Color(red: 0.67, green: 0.69, blue: 0.66)
    static let openLARPPanel = Color.white
}

struct Card<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .background(Color.openLARPPanel)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 6)
    }
}

struct Pill: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
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
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(configuration.isPressed ? Color.openLARPGreen.opacity(0.75) : Color.openLARPGreen)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.openLARPInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(configuration.isPressed ? Color.openLARPYellow.opacity(0.35) : Color.openLARPYellow.opacity(0.22))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
