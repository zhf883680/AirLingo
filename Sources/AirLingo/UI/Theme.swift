import SwiftUI

enum Theme {
    static let bg = Color(hex: 0x030208)
    static let bgSoft = Color(hex: 0x08060F)
    static let panel = Color(hex: 0x0B0916)
    static let surface = Color.white.opacity(0.045)
    static let surfaceHi = Color.white.opacity(0.075)
    static let line = Color.white.opacity(0.07)
    static let lineHi = Color.white.opacity(0.16)
    static let fg = Color(hex: 0xF4F2FF)
    static let fgSoft = Color(hex: 0xF4F2FF).opacity(0.62)
    static let brand = Color(hex: 0x6831FF)
    static let brandLite = Color(hex: 0xA78BFA)
    static let radius: CGFloat = 16
    static let cardRadius: CGFloat = 14

    static let titleGradient = LinearGradient(
        colors: [Color(hex: 0xC4B5FD), Color(hex: 0x7C3AED)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let bgGlow = RadialGradient(
        colors: [Color(hex: 0x2A1B5E).opacity(0.55), .clear],
        center: .top,
        startRadius: 10,
        endRadius: 620
    )
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

struct GlassCard: ViewModifier {
    var padding: CGFloat = 20
    var radius: CGFloat = Theme.cardRadius

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Theme.line, lineWidth: 1)
            )
    }
}

extension View {
    func glassCard(padding: CGFloat = 20, radius: CGFloat = Theme.cardRadius) -> some View {
        modifier(GlassCard(padding: padding, radius: radius))
    }

    func airToolbarButton() -> some View {
        self
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.fgSoft)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(Theme.surface)
            )
            .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.fg)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.fgSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(Theme.fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x2B2740), Color(hex: 0x1A1726)], startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }
}
