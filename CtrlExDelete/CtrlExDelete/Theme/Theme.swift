import SwiftUI

// MARK: - Colors
// Every color comes from the `P` palette in CED-Figma-Reference/src/App.tsx.
// Use these names instead of typing hex values inside screens.

extension Color {
    /// Creates a color from a hex value such as 0x35677D.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

enum CEDColor {
    static let background = Color(hex: 0xFFFBF5)   // warm ivory
    static let foreground = Color(hex: 0x2D4052)   // deep slate
    static let card = Color(hex: 0xFFFFFF)
    static let primary = Color(hex: 0x35677D)      // darker blue — buttons, active nav
    static let secondary = Color(hex: 0xE7F1F6)    // powder blue — selected cards
    static let mutedForeground = Color(hex: 0x596979)
    static let accent = Color(hex: 0x5A9CB5)       // main blue — decorative highlights
    static let border = Color(hex: 0xD5E2E8)
    static let rose = Color(hex: 0xE9716D)         // coral — small details
    static let cream = Color(hex: 0xFFFBF5)
    static let peach = Color(hex: 0xEFB073)
    static let hint = Color(hex: 0x8FAABB)         // faint helper text
    static let checkInBackground = Color(hex: 0xEFF6FA)

    // Icon colors used by the check-in emotion cards
    static let sproutGreen = Color(hex: 0x6BA84A)
    static let sunriseAmber = Color(hex: 0xE8A030)

    // Ced and the pixel room use the original warm palette
    static let walnut = Color(hex: 0x3D2B1F)
    static let ghostBody = Color(hex: 0xF0EEFF)
    static let ghostCheek = Color(hex: 0xF09090)
}

// MARK: - Fonts
// Lora (headings) and Nunito (body) are bundled in Resources/Fonts
// and registered at launch by FontRegistrar.

enum CEDFontName: String, CaseIterable {
    case loraRegular = "Lora-Regular"
    case loraMedium = "Lora-Medium"
    case loraSemiBold = "Lora-SemiBold"
    case loraBold = "Lora-Bold"
    case loraItalic = "Lora-Italic"
    case loraMediumItalic = "Lora-MediumItalic"
    case nunitoRegular = "Nunito-Regular"
    case nunitoMedium = "Nunito-Medium"
    case nunitoSemiBold = "Nunito-SemiBold"
    case nunitoBold = "Nunito-Bold"
    case nunitoExtraBold = "Nunito-ExtraBold"
}

// MARK: - Text styles
// Each style copies a font size, line height and letter spacing from the
// prototype's Tailwind classes (for example `text-sm` = 14pt with a 20pt line).

struct CEDTextStyle {
    let font: CEDFontName
    let size: CGFloat
    let lineHeight: CGFloat
    var tracking: CGFloat = 0
    var relativeTo: Font.TextStyle = .body

    func tracking(_ value: CGFloat) -> CEDTextStyle {
        var copy = self
        copy.tracking = value
        return copy
    }

    // Headings (Lora)
    static let welcomeTitle = CEDTextStyle(font: .loraBold, size: 38, lineHeight: 38, tracking: -0.76, relativeTo: .largeTitle)
    static let screenTitle = CEDTextStyle(font: .loraBold, size: 26, lineHeight: 32.5, relativeTo: .title)
    static let pageTitle = CEDTextStyle(font: .loraBold, size: 24, lineHeight: 32, relativeTo: .title)
    static let cardTitle = CEDTextStyle(font: .loraBold, size: 20, lineHeight: 28, relativeTo: .title3)
    static let bigNumber = CEDTextStyle(font: .loraBold, size: 24, lineHeight: 32, relativeTo: .title2)
    static let finalTitle = CEDTextStyle(font: .loraBold, size: 30, lineHeight: 36, relativeTo: .largeTitle)
    static let sheetTitle = CEDTextStyle(font: .loraBold, size: 18, lineHeight: 28, relativeTo: .title3)
    static let sectionTitle = CEDTextStyle(font: .loraBold, size: 16, lineHeight: 24, relativeTo: .headline)
    static let serifLabel = CEDTextStyle(font: .loraSemiBold, size: 14, lineHeight: 20, relativeTo: .subheadline)
    static let serifBodyBold = CEDTextStyle(font: .loraBold, size: 14, lineHeight: 20, relativeTo: .subheadline)

    // Body (Nunito)
    static let eyebrow = CEDTextStyle(font: .nunitoBold, size: 12, lineHeight: 16, tracking: 2.4, relativeTo: .caption)
    static let body = CEDTextStyle(font: .nunitoRegular, size: 14, lineHeight: 20, relativeTo: .subheadline)
    static let bodyRelaxed = CEDTextStyle(font: .nunitoRegular, size: 14, lineHeight: 22.75, relativeTo: .subheadline)
    static let bodySemibold = CEDTextStyle(font: .nunitoSemiBold, size: 14, lineHeight: 20, relativeTo: .subheadline)
    static let bodyBold = CEDTextStyle(font: .nunitoBold, size: 14, lineHeight: 20, relativeTo: .subheadline)
    static let caption = CEDTextStyle(font: .nunitoRegular, size: 12, lineHeight: 16, relativeTo: .caption)
    static let captionBold = CEDTextStyle(font: .nunitoBold, size: 12, lineHeight: 16, relativeTo: .caption)
    static let toast = CEDTextStyle(font: .nunitoBold, size: 13, lineHeight: 19.5, relativeTo: .footnote)
    static let captionSemibold = CEDTextStyle(font: .nunitoSemiBold, size: 12, lineHeight: 16, relativeTo: .caption)
    static let bodyLarge = CEDTextStyle(font: .nunitoRegular, size: 16, lineHeight: 24, relativeTo: .body)
    static let memoryQuote = CEDTextStyle(font: .nunitoRegular, size: 11, lineHeight: 15.125, relativeTo: .caption2)
    static let small = CEDTextStyle(font: .nunitoRegular, size: 10, lineHeight: 15, relativeTo: .caption2)
    static let smallSnug = CEDTextStyle(font: .nunitoRegular, size: 10, lineHeight: 13.75, relativeTo: .caption2)
    static let smallBold = CEDTextStyle(font: .nunitoBold, size: 10, lineHeight: 15, relativeTo: .caption2)
    static let smallSemibold = CEDTextStyle(font: .nunitoSemiBold, size: 10, lineHeight: 15, relativeTo: .caption2)
    static let tinyBold = CEDTextStyle(font: .nunitoBold, size: 9, lineHeight: 13.5, relativeTo: .caption2)
    static let navLabel = CEDTextStyle(font: .nunitoBold, size: 10, lineHeight: 15, tracking: 0.25, relativeTo: .caption2)
    static let tiny = CEDTextStyle(font: .nunitoRegular, size: 9, lineHeight: 13.5, relativeTo: .caption2)
    static let button = CEDTextStyle(font: .nunitoBold, size: 16, lineHeight: 24, relativeTo: .body)
}

extension View {
    /// Applies a CED font, line height and letter spacing in one step.
    func cedTextStyle(_ style: CEDTextStyle) -> some View {
        // SwiftUI spaces lines by the font's own height, so we add the
        // difference to reach the prototype's CSS line height.
        let extra = style.lineHeight - FontMetrics.naturalLineHeight(of: style.font, size: style.size)
        return self
            .font(.custom(style.font.rawValue, size: style.size, relativeTo: style.relativeTo))
            .tracking(style.tracking)
            .lineSpacing(max(extra, 0))
            .padding(.vertical, extra / 2)
    }
}

// MARK: - Shapes & spacing

enum CEDRadius {
    static let lg: CGFloat = 12      // rounded-xl
    static let xl: CGFloat = 16      // rounded-2xl
    static let xxl: CGFloat = 24     // rounded-3xl
}
