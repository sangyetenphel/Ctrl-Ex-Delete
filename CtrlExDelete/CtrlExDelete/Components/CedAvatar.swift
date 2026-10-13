import SwiftUI

/// Small pixel Ced used in the chat, redrawn from `CedAvatar` in App.tsx
/// (a 32 × 32 grid on a rounded powder-blue tile).
struct CedAvatar: View {
    var size: CGFloat = 32

    var body: some View {
        Canvas { c, canvasSize in
            let scale = canvasSize.width / 32
            c.scaleBy(x: scale, y: scale)

            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ hex: UInt32, _ opacity: Double = 1) {
                c.fill(Path(CGRect(x: x, y: y, width: w, height: h)), with: .color(Color(hex: hex, opacity: opacity)))
            }

            c.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: 32, height: 32), cornerRadius: 10),
                   with: .color(CEDColor.secondary))
            // Body
            rect(9, 14, 14, 12, 0xF0EEFF)
            rect(11, 8, 10, 8, 0xF0EEFF)
            rect(12, 6, 8, 4, 0xF0EEFF)
            // Wavy hem
            rect(9, 24, 3, 3, 0xF0EEFF)
            rect(13, 26, 3, 3, 0xF0EEFF)
            rect(17, 24, 3, 3, 0xF0EEFF)
            rect(21, 26, 2, 3, 0xF0EEFF)
            // Eyes and sparkles
            rect(13, 11, 2, 3, 0x3D2B1F)
            rect(17, 11, 2, 3, 0x3D2B1F)
            rect(14, 11, 1, 1, 0xFFFFFF)
            rect(18, 11, 1, 1, 0xFFFFFF)
            // Cheeks
            rect(10, 13, 3, 2, 0xF09090, 0.5)
            rect(19, 13, 3, 2, 0xF09090, 0.5)
            // Smile
            rect(14, 15, 1, 1, 0x3D2B1F)
            rect(15, 16, 3, 1, 0x3D2B1F)
            rect(17, 15, 1, 1, 0x3D2B1F)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
