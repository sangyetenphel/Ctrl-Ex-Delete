import CoreText
import SwiftUI
#if canImport(UIKit)
import UIKit
private typealias PlatformFont = UIFont
#else
import AppKit
private typealias PlatformFont = NSFont
#endif

/// Makes the bundled Lora and Nunito font files available to the app.
/// Call `registerBundledFonts()` once when the app starts (see MyApp.swift).
enum FontRegistrar {
    static func registerBundledFonts() {
        let fontURLs = (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
            + (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? [])

        for url in fontURLs {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }

        #if DEBUG
        // Warn in the Xcode console if a font is missing, instead of
        // silently falling back to the system font.
        for name in CEDFontName.allCases where PlatformFont(name: name.rawValue, size: 12) == nil {
            print("Warning: CED font not found: \(name.rawValue)")
        }
        #endif
    }
}

/// Reads font measurements so text styles can match CSS line heights.
enum FontMetrics {
    static func naturalLineHeight(of font: CEDFontName, size: CGFloat) -> CGFloat {
        guard let platformFont = PlatformFont(name: font.rawValue, size: size) else { return size * 1.2 }
        return platformFont.ascender - platformFont.descender + platformFont.leading
    }

    /// Distance from the top of a line of text to its baseline.
    static func ascender(of font: CEDFontName, size: CGFloat) -> CGFloat {
        PlatformFont(name: font.rawValue, size: size)?.ascender ?? size * 0.9
    }
}
