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
