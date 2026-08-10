import SwiftUI
import AppKit

// MARK: - Enums

enum Appearance: String, CaseIterable, Codable {
    case system, light, dark
    var title: String {
        switch self {
        case .system: return "Follow System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

/// A dashboard column.
enum Pane: String, CaseIterable, Codable, Identifiable {
    case claude, codex, omlx
    var id: String { rawValue }
    var title: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .omlx: return "OMLX"
        }
    }
}

/// How usage bars are coloured.
enum BarColorMode: String, CaseIterable, Codable {
    case accentRedHigh   // provider accent, red only past the danger threshold (default)
    case ramp            // accent < warn, warn colour, danger colour — same rule everywhere
    case accentOnly      // always the provider accent, never changes

    var title: String {
        switch self {
        case .accentRedHigh: return "Accent, alert at high %"
        case .ramp: return "Accent → Warn → Danger"
        case .accentOnly: return "Accent only (no change)"
        }
    }
    /// Warning/danger colours are meaningless (and disabled in the UI) in this mode.
    var usesAlertColors: Bool { self != .accentOnly }
}

// MARK: - Typefaces

enum Typeface: String, CaseIterable, Codable, Identifiable {
    case sfMono, menlo                       // mono
    case newYork, charter                    // serif
    case sfPro, sfRounded, helveticaNeue, avenirNext   // sans

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sfMono: return "SF Mono"
        case .menlo: return "Menlo"
        case .newYork: return "New York"
        case .charter: return "Charter"
        case .sfPro: return "SF Pro"
        case .sfRounded: return "SF Rounded"
        case .helveticaNeue: return "Helvetica Neue"
        case .avenirNext: return "Avenir Next"
        }
    }

    enum Category: String { case mono = "Monospace", serif = "Serif", sans = "Sans-serif" }
    var category: Category {
        switch self {
        case .sfMono, .menlo: return .mono
        case .newYork, .charter: return .serif
        default: return .sans
        }
    }

    func font(size: CGFloat, weight: Font.Weight) -> Font {
        switch self {
        case .sfMono: return .system(size: size, weight: weight, design: .monospaced)
        case .menlo: return .custom("Menlo", size: size).weight(weight)
        case .newYork: return .system(size: size, weight: weight, design: .serif)
        case .charter: return .custom("Charter", size: size).weight(weight)
        case .sfPro: return .system(size: size, weight: weight, design: .default)
        case .sfRounded: return .system(size: size, weight: weight, design: .rounded)
        case .helveticaNeue: return .custom("Helvetica Neue", size: size).weight(weight)
        case .avenirNext: return .custom("Avenir Next", size: size).weight(weight)
        }
    }
}

// MARK: - Templates

/// A complete aesthetic preset. Selecting one resets fonts/weights/accents/alert
/// colours to the template's look; the surfaces (background/text) come from `spec`.
enum Template: String, CaseIterable, Codable, Identifiable {
    case terminal, material, cupertino, editorial, luxe

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terminal: return "Terminal"
        case .material: return "Material"
        case .cupertino: return "Cupertino"
        case .editorial: return "Editorial"
        case .luxe: return "Luxe"
        }
    }
    var blurb: String {
        switch self {
        case .terminal: return "Monospaced, near-black, sharp. The original."
        case .material: return "Material-inspired: SF Pro, bold headers, soft surfaces."
        case .cupertino: return "Apple HIG: SF Rounded, gentle, translucent-feeling."
        case .editorial: return "Serif, high-contrast, magazine-like."
        case .luxe: return "Refined mono/serif mix, warm ink on paper."
        }
    }

    struct Spec {
        var body: Typeface, number: Typeface
        var bodyBold: Bool, numberBold: Bool
        var corner: CGFloat            // bar corner radius (large = capsule)
        var claude, codex, omlx: String   // default accent hex
        var warn, danger: String
        var darkBg, darkSurface, darkText: String
        var lightBg, lightSurface, lightText: String
    }

    var spec: Spec {
        switch self {
        case .terminal:
            return Spec(body: .sfMono, number: .sfMono, bodyBold: false, numberBold: false, corner: 5,
                        claude: "#D9785A", codex: "#10A37F", omlx: "#7B8CFF", warn: "#F2BF40", danger: "#F0594D",
                        darkBg: "#0E0E12", darkSurface: "#16161C", darkText: "#FFFFFF",
                        lightBg: "#F7F7F5", lightSurface: "#FFFFFF", lightText: "#14141A")
        case .material:
            return Spec(body: .sfPro, number: .sfPro, bodyBold: true, numberBold: true, corner: 8,
                        claude: "#FF7043", codex: "#26A69A", omlx: "#5C6BC0", warn: "#FFB300", danger: "#EF5350",
                        darkBg: "#121212", darkSurface: "#1E1E1E", darkText: "#FFFFFF",
                        lightBg: "#FEFBFF", lightSurface: "#FFFFFF", lightText: "#1C1B1F")
        case .cupertino:
            return Spec(body: .sfRounded, number: .sfRounded, bodyBold: false, numberBold: true, corner: 10,
                        claude: "#FF9F0A", codex: "#30D158", omlx: "#0A84FF", warn: "#FFD60A", danger: "#FF453A",
                        darkBg: "#1C1C1E", darkSurface: "#2C2C2E", darkText: "#FFFFFF",
                        lightBg: "#F2F2F7", lightSurface: "#FFFFFF", lightText: "#1C1C1E")
        case .editorial:
            return Spec(body: .newYork, number: .newYork, bodyBold: false, numberBold: true, corner: 3,
                        claude: "#C0603A", codex: "#2F8F6B", omlx: "#4B5BC4", warn: "#C99A2E", danger: "#C6483C",
                        darkBg: "#14110E", darkSurface: "#1E1A16", darkText: "#F5EFE6",
                        lightBg: "#FBF7EF", lightSurface: "#FFFFFF", lightText: "#1A1510")
        case .luxe:
            return Spec(body: .charter, number: .sfMono, bodyBold: false, numberBold: false, corner: 4,
                        claude: "#B5835A", codex: "#3C8A72", omlx: "#6C7BD6", warn: "#CBA135", danger: "#C85A4E",
                        darkBg: "#101014", darkSurface: "#191920", darkText: "#EDE8E0",
                        lightBg: "#F4F1EA", lightSurface: "#FBFAF6", lightText: "#1B1B22")
        }
    }
}

// MARK: - Palette (resolved colours for the current appearance)

struct Palette {
    let bg, surface, divider: Color
    let textPrimary, textSecondary, textTertiary: Color
    let claudeAccent, codexAccent, omlxAccent: Color
    let warn, danger: Color
    let corner: CGFloat

    func accent(_ pane: Pane) -> Color {
        switch pane {
        case .claude: return claudeAccent
        case .codex: return codexAccent
        case .omlx: return omlxAccent
        }
    }
}

// MARK: - Preset colours (32: ~16 tuned for light bg, ~16 for dark bg, brand included)

struct PresetColor: Identifiable {
    let name: String, hex: String, forDark: Bool
    var id: String { hex }
}

enum Presets {
    /// Brighter, slightly desaturated tones that pop on dark backgrounds.
    static let dark: [PresetColor] = [
        .init(name: "Claude", hex: "#D9785A", forDark: true),
        .init(name: "Codex", hex: "#10A37F", forDark: true),
        .init(name: "Periwinkle", hex: "#7B8CFF", forDark: true),
        .init(name: "Sky", hex: "#4AA9E0", forDark: true),
        .init(name: "Mint", hex: "#3DD6A8", forDark: true),
        .init(name: "Lime", hex: "#B5D14A", forDark: true),
        .init(name: "Amber", hex: "#F2BF40", forDark: true),
        .init(name: "Coral", hex: "#FF7A66", forDark: true),
        .init(name: "Rose", hex: "#FF6F9C", forDark: true),
        .init(name: "Orchid", hex: "#C57BFF", forDark: true),
        .init(name: "Violet", hex: "#9A7BFF", forDark: true),
        .init(name: "Teal", hex: "#2FD4C4", forDark: true),
        .init(name: "Gold", hex: "#E7C568", forDark: true),
        .init(name: "Salmon", hex: "#F08A6C", forDark: true),
        .init(name: "Aqua", hex: "#5FD0E0", forDark: true),
        .init(name: "Slate", hex: "#9AA7C7", forDark: true),
    ]
    /// Deeper, saturated tones that stay legible on light backgrounds.
    static let light: [PresetColor] = [
        .init(name: "Anthropic", hex: "#CC785C", forDark: false),
        .init(name: "OpenAI", hex: "#0B8F70", forDark: false),
        .init(name: "Indigo", hex: "#4B5BC4", forDark: false),
        .init(name: "Ocean", hex: "#1E7FC2", forDark: false),
        .init(name: "Emerald", hex: "#1E9E74", forDark: false),
        .init(name: "Olive", hex: "#7E8C2E", forDark: false),
        .init(name: "Ochre", hex: "#C99A2E", forDark: false),
        .init(name: "Rust", hex: "#C0603A", forDark: false),
        .init(name: "Magenta", hex: "#C43E7A", forDark: false),
        .init(name: "Plum", hex: "#8A4BC4", forDark: false),
        .init(name: "Grape", hex: "#6B4BC4", forDark: false),
        .init(name: "Pine", hex: "#1F8A78", forDark: false),
        .init(name: "Bronze", hex: "#A9762F", forDark: false),
        .init(name: "Brick", hex: "#B44A3C", forDark: false),
        .init(name: "Cerulean", hex: "#2C8DB0", forDark: false),
        .init(name: "Graphite", hex: "#5A6478", forDark: false),
    ]
    static let all: [PresetColor] = dark + light
}

// MARK: - Color <-> hex

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .white
        return String(format: "#%02X%02X%02X",
                      Int(round(ns.redComponent * 255)),
                      Int(round(ns.greenComponent * 255)),
                      Int(round(ns.blueComponent * 255)))
    }
    static func fromHex(_ hex: String, fallback: Color = .gray) -> Color { Color(hex: hex) ?? fallback }
}

// MARK: - AppSettings

@MainActor
final class AppSettings: ObservableObject {
    @Published var template: Template { didSet { if !loading { save() } } }
    @Published var appearance: Appearance { didSet { if !loading { save() } } }
    @Published var bodyTypeface: Typeface { didSet { if !loading { save() } } }
    @Published var numberTypeface: Typeface { didSet { if !loading { save() } } }
    @Published var bodyBold: Bool { didSet { if !loading { save() } } }
    @Published var numberBold: Bool { didSet { if !loading { save() } } }
    @Published var barColorMode: BarColorMode { didSet { if !loading { save() } } }
    @Published var showPace: Bool { didSet { if !loading { save() } } }
    @Published var claudeAccentHex: String { didSet { if !loading { save() } } }
    @Published var codexAccentHex: String { didSet { if !loading { save() } } }
    @Published var omlxAccentHex: String { didSet { if !loading { save() } } }
    @Published var warnHex: String { didSet { if !loading { save() } } }
    @Published var dangerHex: String { didSet { if !loading { save() } } }
    @Published var warnThreshold: Double { didSet { if !loading { save() } } }
    @Published var dangerThreshold: Double { didSet { if !loading { save() } } }
    @Published var columns: [Pane] { didSet { if !loading { save() } } }

    /// Live system dark/light, updated by the app on appearance changes. Not persisted.
    @Published var systemIsDark: Bool = true

    private var loading = false

    var effectiveDark: Bool {
        switch appearance {
        case .dark: return true
        case .light: return false
        case .system: return systemIsDark
        }
    }

    var palette: Palette {
        let s = template.spec
        let dark = effectiveDark
        let bg = Color.fromHex(dark ? s.darkBg : s.lightBg)
        let surface = Color.fromHex(dark ? s.darkSurface : s.lightSurface)
        let text = Color.fromHex(dark ? s.darkText : s.lightText)
        return Palette(
            bg: bg,
            surface: surface,
            divider: text.opacity(dark ? 0.10 : 0.12),
            textPrimary: text.opacity(dark ? 0.92 : 0.90),
            textSecondary: text.opacity(dark ? 0.58 : 0.60),
            textTertiary: text.opacity(dark ? 0.34 : 0.40),
            claudeAccent: .fromHex(claudeAccentHex),
            codexAccent: .fromHex(codexAccentHex),
            omlxAccent: .fromHex(omlxAccentHex),
            warn: .fromHex(warnHex),
            danger: .fromHex(dangerHex),
            corner: s.corner)
    }

    /// The panes to render, in order — those the user enabled and (for OMLX) configured.
    func visiblePanes(omlxConfigured: Bool) -> [Pane] {
        columns.filter { $0 != .omlx || omlxConfigured }
    }

    init() {
        // Defaults (Terminal template).
        let s = Template.terminal.spec
        template = .terminal
        appearance = .system
        bodyTypeface = s.body
        numberTypeface = s.number
        bodyBold = s.bodyBold
        numberBold = s.numberBold
        barColorMode = .accentRedHigh
        showPace = true
        claudeAccentHex = s.claude
        codexAccentHex = s.codex
        omlxAccentHex = s.omlx
        warnHex = s.warn
        dangerHex = s.danger
        warnThreshold = 70
        dangerThreshold = 90
        columns = [.claude, .codex, .omlx]
        load()
    }

    /// Reset fonts/accents/alert colours to the given template's look.
    func applyTemplate(_ t: Template) {
        loading = true
        let s = t.spec
        template = t
        bodyTypeface = s.body
        numberTypeface = s.number
        bodyBold = s.bodyBold
        numberBold = s.numberBold
        claudeAccentHex = s.claude
        codexAccentHex = s.codex
        omlxAccentHex = s.omlx
        warnHex = s.warn
        dangerHex = s.danger
        loading = false
        save()
    }

    // MARK: Persistence

    private struct Data: Codable {
        var template, appearance, bodyTypeface, numberTypeface, barColorMode: String
        var bodyBold, numberBold, showPace: Bool
        var claudeAccentHex, codexAccentHex, omlxAccentHex, warnHex, dangerHex: String
        var warnThreshold, dangerThreshold: Double
        var columns: [String]
    }

    private var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/moongazer/settings.json")
    }

    private func load() {
        guard
            let raw = try? Foundation.Data(contentsOf: fileURL),
            let d = try? JSONDecoder().decode(Data.self, from: raw)
        else { return }
        loading = true
        template = Template(rawValue: d.template) ?? template
        appearance = Appearance(rawValue: d.appearance) ?? appearance
        bodyTypeface = Typeface(rawValue: d.bodyTypeface) ?? bodyTypeface
        numberTypeface = Typeface(rawValue: d.numberTypeface) ?? numberTypeface
        barColorMode = BarColorMode(rawValue: d.barColorMode) ?? barColorMode
        bodyBold = d.bodyBold
        numberBold = d.numberBold
        showPace = d.showPace
        claudeAccentHex = d.claudeAccentHex
        codexAccentHex = d.codexAccentHex
        omlxAccentHex = d.omlxAccentHex
        warnHex = d.warnHex
        dangerHex = d.dangerHex
        warnThreshold = d.warnThreshold
        dangerThreshold = d.dangerThreshold
        let panes = d.columns.compactMap { Pane(rawValue: $0) }
        if !panes.isEmpty { columns = panes }
        loading = false
    }

    private func save() {
        let d = Data(
            template: template.rawValue, appearance: appearance.rawValue,
            bodyTypeface: bodyTypeface.rawValue, numberTypeface: numberTypeface.rawValue,
            barColorMode: barColorMode.rawValue,
            bodyBold: bodyBold, numberBold: numberBold, showPace: showPace,
            claudeAccentHex: claudeAccentHex, codexAccentHex: codexAccentHex,
            omlxAccentHex: omlxAccentHex, warnHex: warnHex, dangerHex: dangerHex,
            warnThreshold: warnThreshold, dangerThreshold: dangerThreshold,
            columns: columns.map { $0.rawValue })
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let raw = try? JSONEncoder().encode(d) { try? raw.write(to: fileURL, options: .atomic) }
    }
}
