import SwiftUI
import BitlatheCore

/// Design tokens — see Docs/DesignSystem.md. Never use raw numbers in views.
public enum Space {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
    public static let xxxl: CGFloat = 48
}

public enum Radius {
    public static let small: CGFloat = 6
    public static let medium: CGFloat = 10
    public static let large: CGFloat = 14
    public static let panel: CGFloat = 18
}

public enum Layout {
    public static let headerHeight: CGFloat = 48
    public static let optionBarHeight: CGFloat = 36
    public static let statusHeight: CGFloat = 24
    public static let sidebarMin: CGFloat = 220
    public static let sidebarIdeal: CGFloat = 250
    public static let sidebarMax: CGFloat = 320
    public static let inspectorMin: CGFloat = 260
    public static let inspectorIdeal: CGFloat = 300
    public static let inspectorMax: CGFloat = 380
    public static let minWindow = CGSize(width: 900, height: 600)
}

public enum Motion {
    public static let fast: Double = 0.12
    public static let normal: Double = 0.2

    @MainActor
    public static func animation(_ duration: Double = fast) -> Animation? {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || Settings.shared.reduceMotionOverride { return nil }
        return .easeOut(duration: duration)
    }
}

public enum Typography {
    public static let title: Font = .title2.weight(.semibold)
    public static let headline: Font = .headline
    public static let body: Font = .body
    public static let caption: Font = .caption
    public static let captionMono: Font = .system(size: 11, design: .monospaced)

    @MainActor
    public static var mono: Font {
        .system(size: Settings.shared.effectiveMonoSize, design: .monospaced)
    }
    @MainActor
    public static var monoSmall: Font {
        .system(size: max(9, Settings.shared.effectiveMonoSize - 2), design: .monospaced)
    }
    @MainActor
    public static var nsMono: NSFont {
        let s = Settings.shared
        return NSFont(name: s.editorFontName, size: s.effectiveMonoSize) ?? .monospacedSystemFont(ofSize: s.effectiveMonoSize, weight: .regular)
    }
}

public enum Palette {
    public static let appAccentLight = Color(red: 0.24, green: 0.48, blue: 1.0)
    public static let appAccentDark = Color(red: 0.36, green: 0.58, blue: 1.0)
    // Status colours are tuned so text in them reaches WCAG AA (>= 4.5:1) on chrome and on their own 14% tint,
    // in light and dark (system green/orange are only ~2.1:1 on white).
    public static let success = adaptive(light: (0.04, 0.42, 0.16), dark: (0.30, 0.85, 0.45))
    public static let warning = adaptive(light: (0.60, 0.28, 0.0), dark: (1.0, 0.65, 0.25))
    public static let danger = adaptive(light: (0.70, 0.07, 0.06), dark: (1.0, 0.50, 0.47))
    /// Low-emphasis text that still meets AA (system tertiary label is only ~1.9:1 light / 2.3:1 dark).
    public static let subtle = adaptive(light: (0.38, 0.38, 0.38), dark: (0.66, 0.66, 0.66))
    private static func adaptive(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(nsColor: NSColor(name: nil) { a in
            let c = a.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
    public static let editorBackground = Color(nsColor: .textBackgroundColor)
    public static let raised = Color(nsColor: .quaternarySystemFill)
    public static let separator = Color(nsColor: .separatorColor)
    /// Solid chrome for header / option bar / status strip (no translucency over content).
    public static let chrome = Color(nsColor: NSColor(name: nil) { a in
        a.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(white: 0.155, alpha: 1) : NSColor(white: 0.975, alpha: 1)
    })
    public static let paneTitle = Color(nsColor: NSColor(name: nil) { a in
        a.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(white: 0.135, alpha: 1) : NSColor(white: 0.955, alpha: 1)
    })

    @MainActor
    public static var accent: Color {
        Settings.shared.useAppAccent ? appAccentLight : .accentColor
    }
}

// MARK: - Editor themes

public struct EditorTheme: Identifiable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var light: Colors
    public var dark: Colors

    public struct Colors: Sendable, Hashable {
        public var background: UInt32
        public var text: UInt32
        public var keyword: UInt32
        public var string: UInt32
        public var number: UInt32
        public var comment: UInt32
        public var key: UInt32
        public var punctuation: UInt32
        public var tag: UInt32
        public var attribute: UInt32
        public var currentLine: UInt32
        public var gutter: UInt32
        public var gutterText: UInt32
    }

    public static let all: [EditorTheme] = [
        EditorTheme(id: "bitlathe", name: "Bitlathe",
                    light: .init(background: 0xFFFFFF, text: 0x1D1D1F, keyword: 0xA626A4, string: 0x50A14F, number: 0x986801, comment: 0xA0A1A7, key: 0x4078F2, punctuation: 0x383A42, tag: 0xE45649, attribute: 0x986801, currentLine: 0xF5F7FA, gutter: 0xFAFAFA, gutterText: 0x9D9D9D),
                    dark: .init(background: 0x1E1E22, text: 0xE6E6E6, keyword: 0xC678DD, string: 0x98C379, number: 0xD19A66, comment: 0x6B6F76, key: 0x61AFEF, punctuation: 0xABB2BF, tag: 0xE06C75, attribute: 0xD19A66, currentLine: 0x26262B, gutter: 0x1B1B1F, gutterText: 0x5C5F66)),
        EditorTheme(id: "paper", name: "Paper",
                    light: .init(background: 0xFDFBF7, text: 0x2B2B2B, keyword: 0x8F3F71, string: 0x79740E, number: 0xB57614, comment: 0x928374, key: 0x076678, punctuation: 0x3C3836, tag: 0x9D0006, attribute: 0xAF3A03, currentLine: 0xF5F1E8, gutter: 0xF7F3EA, gutterText: 0xA89984),
                    dark: .init(background: 0x282828, text: 0xEBDBB2, keyword: 0xD3869B, string: 0xB8BB26, number: 0xFABD2F, comment: 0x928374, key: 0x83A598, punctuation: 0xD5C4A1, tag: 0xFB4934, attribute: 0xFE8019, currentLine: 0x32302F, gutter: 0x242424, gutterText: 0x7C6F64)),
        EditorTheme(id: "graphite", name: "Graphite",
                    light: .init(background: 0xF7F7F8, text: 0x1F2328, keyword: 0xCF222E, string: 0x0A3069, number: 0x0550AE, comment: 0x6E7781, key: 0x8250DF, punctuation: 0x24292F, tag: 0x116329, attribute: 0x0550AE, currentLine: 0xEFF1F3, gutter: 0xF1F2F4, gutterText: 0x8C959F),
                    dark: .init(background: 0x0D1117, text: 0xE6EDF3, keyword: 0xFF7B72, string: 0xA5D6FF, number: 0x79C0FF, comment: 0x8B949E, key: 0xD2A8FF, punctuation: 0xC9D1D9, tag: 0x7EE787, attribute: 0x79C0FF, currentLine: 0x161B22, gutter: 0x0B0F14, gutterText: 0x484F58)),
        EditorTheme(id: "solar", name: "Solar",
                    light: .init(background: 0xFDF6E3, text: 0x586E75, keyword: 0x859900, string: 0x2AA198, number: 0xD33682, comment: 0x93A1A1, key: 0x268BD2, punctuation: 0x657B83, tag: 0xCB4B16, attribute: 0xB58900, currentLine: 0xEEE8D5, gutter: 0xF5EFDC, gutterText: 0x93A1A1),
                    dark: .init(background: 0x002B36, text: 0x93A1A1, keyword: 0x859900, string: 0x2AA198, number: 0xD33682, comment: 0x586E75, key: 0x268BD2, punctuation: 0x839496, tag: 0xCB4B16, attribute: 0xB58900, currentLine: 0x073642, gutter: 0x00252F, gutterText: 0x586E75)),
        EditorTheme(id: "midnight", name: "Midnight",
                    light: .init(background: 0xFFFFFF, text: 0x24292E, keyword: 0x005CC5, string: 0x032F62, number: 0xE36209, comment: 0x6A737D, key: 0x6F42C1, punctuation: 0x24292E, tag: 0x22863A, attribute: 0x6F42C1, currentLine: 0xF6F8FA, gutter: 0xFAFBFC, gutterText: 0x959DA5),
                    dark: .init(background: 0x11131A, text: 0xD6DEEB, keyword: 0xC792EA, string: 0xECC48D, number: 0xF78C6C, comment: 0x637777, key: 0x82AAFF, punctuation: 0xC5E4FD, tag: 0x7FDBCA, attribute: 0xADDB67, currentLine: 0x181B25, gutter: 0x0E1016, gutterText: 0x4B5263)),
        EditorTheme(id: "mono", name: "Monochrome",
                    light: .init(background: 0xFFFFFF, text: 0x111111, keyword: 0x111111, string: 0x444444, number: 0x111111, comment: 0x999999, key: 0x111111, punctuation: 0x777777, tag: 0x111111, attribute: 0x444444, currentLine: 0xF4F4F4, gutter: 0xF9F9F9, gutterText: 0xAAAAAA),
                    dark: .init(background: 0x161616, text: 0xEDEDED, keyword: 0xEDEDED, string: 0xBBBBBB, number: 0xEDEDED, comment: 0x666666, key: 0xEDEDED, punctuation: 0x888888, tag: 0xEDEDED, attribute: 0xBBBBBB, currentLine: 0x1E1E1E, gutter: 0x121212, gutterText: 0x555555)),
    ]

    public static func named(_ id: String) -> EditorTheme { all.first { $0.id == id } ?? all[0] }
}

public extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

public extension View {
    func cardStyle() -> some View {
        self.background(Palette.raised, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
    }
}
