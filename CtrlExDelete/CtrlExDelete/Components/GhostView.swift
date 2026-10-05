import SwiftUI

/// Ced, the ghost logo from the welcome screen.
/// This redraws the `Ghost` SVG from App.tsx, which uses an 80 × 92 grid.
struct GhostView: View {
    var size: CGFloat = 80

    var body: some View {
        Canvas { context, canvasSize in
            let scale = canvasSize.width / 80
            context.scaleBy(x: scale, y: scale)

            // Soft shadow under Ced
            context.fill(
                Path(ellipseIn: CGRect(x: 23, y: 84, width: 34, height: 8)),
                with: .color(CEDColor.walnut.opacity(0.1))
            )

            // Body: round head, straight sides and a wavy hem.
            // Filled one by one (like the SVG) so overlapping parts don't cancel out.
            let bodyColor = GraphicsContext.Shading.color(CEDColor.ghostBody)
            context.fill(Path(ellipseIn: CGRect(x: 12, y: 6, width: 56, height: 60)), with: bodyColor)
            context.fill(Path(CGRect(x: 12, y: 36, width: 56, height: 34)), with: bodyColor)
            context.fill(Self.hem, with: bodyColor)

            // Eyes and their white sparkles
            context.fill(Path(ellipseIn: CGRect(x: 22, y: 25, width: 12, height: 14)), with: .color(CEDColor.walnut))
            context.fill(Path(ellipseIn: CGRect(x: 46, y: 25, width: 12, height: 14)), with: .color(CEDColor.walnut))
            context.fill(Path(ellipseIn: CGRect(x: 27.5, y: 25.5, width: 5, height: 5)), with: .color(.white))
            context.fill(Path(ellipseIn: CGRect(x: 51.5, y: 25.5, width: 5, height: 5)), with: .color(.white))

            // Pink cheeks
            let cheek = GraphicsContext.Shading.color(CEDColor.ghostCheek.opacity(0.5))
            context.fill(Path(ellipseIn: CGRect(x: 10, y: 36, width: 14, height: 10)), with: cheek)
            context.fill(Path(ellipseIn: CGRect(x: 56, y: 36, width: 14, height: 10)), with: cheek)

            // Smile
            var smile = Path()
            smile.move(to: CGPoint(x: 30, y: 46))
            smile.addQuadCurve(to: CGPoint(x: 50, y: 46), control: CGPoint(x: 40, y: 55))
            context.stroke(smile, with: .color(CEDColor.walnut), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
        .frame(width: size, height: size * 1.15)
        .accessibilityLabel("Ced, your healing companion")
    }

    /// The wavy bottom edge: M12 70 Q18 82 24 70 Q30 58 36 70 … L12 67 Z
    private static let hem: Path = {
        var path = Path()
        path.move(to: CGPoint(x: 12, y: 70))
        path.addQuadCurve(to: CGPoint(x: 24, y: 70), control: CGPoint(x: 18, y: 82))
        path.addQuadCurve(to: CGPoint(x: 36, y: 70), control: CGPoint(x: 30, y: 58))
        path.addQuadCurve(to: CGPoint(x: 48, y: 70), control: CGPoint(x: 42, y: 82))
        path.addQuadCurve(to: CGPoint(x: 60, y: 70), control: CGPoint(x: 54, y: 58))
        path.addQuadCurve(to: CGPoint(x: 68, y: 70), control: CGPoint(x: 64, y: 65))
        path.addLine(to: CGPoint(x: 68, y: 67))
        path.addLine(to: CGPoint(x: 12, y: 67))
        path.closeSubpath()
        return path
    }()
}

#Preview {
    GhostView(size: 110)
        .padding()
        .background(CEDColor.background)
}
