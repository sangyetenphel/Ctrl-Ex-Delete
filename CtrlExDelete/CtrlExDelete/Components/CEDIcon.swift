import SwiftUI

/// The prototype's line icons. Each one is the original SVG from App.tsx,
/// stored in Assets.xcassets/Icons and tinted with a color here.
enum CEDIcon: String {
    // Bottom navigation
    case home = "icon-home"
    case clock = "icon-clock"
    case phone = "icon-phone"
    case book = "icon-book"
    case chart = "icon-chart"

    // Check-in emotions
    case cloud = "icon-cloud"
    case sprout = "icon-sprout"
    case moon = "icon-moon"
    case sunrise = "icon-sunrise"

    // Activity cards
    case sun = "icon-sun"
    case zap = "icon-zap"
    case users = "icon-users"
    case xMark = "icon-x"
    case bookmark = "icon-bookmark"
    case bookmarkFilled = "icon-bookmark-filled"

    // Reflection, scrapbook, talk, chat and final screens
    case check = "icon-check"
    case image = "icon-image"
    case camera = "icon-camera"
    case star = "icon-star"
    case download = "icon-download"
    case info = "icon-info"
    case micBold = "icon-mic-bold"
    case send = "icon-send"
}

struct CEDIconView: View {
    let icon: CEDIcon
    var size: CGFloat = 22
    var color: Color = CEDColor.mutedForeground

    var body: some View {
        Image(icon.rawValue)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}
