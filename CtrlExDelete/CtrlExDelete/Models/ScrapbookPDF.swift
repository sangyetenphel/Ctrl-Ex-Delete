import UIKit

// The farewell scrapbook PDF, drawn on the phone with UIGraphicsPDFRenderer.
// Everything here runs off the main thread: it only uses the plain values in
// `ScrapbookContent` (photo bytes already downloaded), so the PDF never
// depends on temporary S3 links.
//
// Look: cream paper in the app's palette, with restrained blush, lavender
// and pale-blue paper accents, photo corners, tape and the odd heart or star.
// The user's words are printed exactly as written; nothing is invented.

/// What goes into the PDF, oldest first within each section.
/// Text is the user's own words, unchanged; labels are the app's own wording.
/// Only completed activities, their photos and the user's own reflection
/// text are printed. Check-in answers and the reflection questions
/// ("Thought about them", "Afterwards") stay in the app and are never shown.
nonisolated struct ScrapbookContent: Sendable {
    struct Memory: Sendable {
        let date: String            // "October 14"
        let shortDate: String       // "Oct 14"
        let note: String?
        let photo: Data?            // JPEG, already downscaled
        let photoNotIncluded: Bool  // the user chose to continue without it
    }

    struct Entry: Sendable {
        let date: String            // "October 14"
        let shortDate: String       // "Oct 14"
        let title: String
        let category: String
        let memory: Memory?
    }

    var dateRange: String?          // "October 14 – October 20, 2026"
    var entries: [Entry] = []
    var otherMemories: [Memory] = []
    var cedImage: Data?             // PNGs of the app's own artwork
    var scrapbookImage: Data?

    var hasEntries: Bool { !entries.isEmpty || !otherMemories.isEmpty }
}

nonisolated enum ScrapbookPDF {
    /// 6 × 8 in, like a small photo book.
    static let pageSize = CGSize(width: 432, height: 576)

    /// Ced's standard letter. The middle paragraph talks about the pages,
    /// so it's only there when the scrapbook has entries.
    static func letter(hasEntries: Bool) -> [String] {
        [
            "Thank you for letting me keep you company for a while.",
            hasEntries ? "Everything in these pages is something you did: a check-in on a hard day, a small step you took, a moment you chose to notice. None of it had to be perfect to count." : nil,
            hasEntries
                ? "Wherever this next chapter goes, you can come back to these pages whenever you want a reminder of how you showed up for yourself. And the room is still here if you ever need it."
                : "Wherever this next chapter goes, the room is still here if you ever need it.",
        ].compactMap { $0 }
    }

    static let closingLines = [
        "There are still good things ahead of you.",
        "You don\u{2019}t have to rush to meet them.",
        "Take your time. Make room for little joys.",
        "And when a hard day comes, it doesn\u{2019}t undo how far you\u{2019}ve come.",
    ]

    static func render(_ content: ScrapbookContent) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "My Ctrl+Ex+Delete scrapbook",
            kCGPDFContextCreator as String: "Ctrl+Ex+Delete",
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: format)
        return renderer.pdfData { context in
            let page = PageWriter(context: context)
            page.cover(content)
            if !content.entries.isEmpty { page.entries(content.entries) }
            if !content.otherMemories.isEmpty { page.otherMemories(content.otherMemories) }
            page.closing(cedImage: content.cedImage)
            page.letter(cedImage: content.cedImage, hasEntries: content.hasEntries)
        }
    }
}

// MARK: - Page layout

private nonisolated final class PageWriter {
    let context: UIGraphicsPDFRendererContext
    let size = ScrapbookPDF.pageSize
    let margin: CGFloat = 40
    var y: CGFloat = 0
    var pageNumber = 0

    var width: CGFloat { size.width - margin * 2 }
    var bottom: CGFloat { size.height - 46 }   // room for the page number
    var room: CGFloat { bottom - y }
    var cg: CGContext { context.cgContext }

    init(context: UIGraphicsPDFRendererContext) {
        self.context = context
    }

    // MARK: Pages

    func newPage(numbered: Bool = true) {
        context.beginPage()
        pageNumber += 1
        Palette.paper.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        y = margin
        if numbered {
            let text = Style.text("Ctrl+Ex+Delete \u{B7} \(pageNumber)", .small, Palette.hint, align: .center)
            text.draw(in: CGRect(x: margin, y: size.height - 30, width: width, height: 14))
        }
    }

    /// A section title that never sits alone at the bottom of a page.
    func section(eyebrow: String, title: String, keepWith next: CGFloat = 90) {
        let eyebrowText = Style.text(eyebrow.uppercased(), .eyebrow, Palette.primary, kern: 1.6)
        let titleText = Style.text(title, .title, Palette.foreground)
        let needed = height(eyebrowText) + 4 + height(titleText) + 14 + next
        if y > margin, room < needed { newPage() }
        // A little star beside the eyebrow.
        let eyebrowWidth = ceil(eyebrowText.size().width)
        star(center: CGPoint(x: margin + eyebrowWidth + 9, y: y + 5), radius: 4, color: Palette.sunrise)
        draw(eyebrowText, after: 4)
        draw(titleText, after: 14)
    }

    // MARK: Cover

    func cover(_ content: ScrapbookContent) {
        newPage(numbered: false)
        Palette.paleBlue.setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: size.width, height: 250))
        // A few quiet decorations on the blue.
        star(center: CGPoint(x: 70, y: 70), radius: 6, color: Palette.white.withAlphaComponent(0.9))
        star(center: CGPoint(x: 360, y: 58), radius: 4.5, color: Palette.sunrise.withAlphaComponent(0.7))
        heart(center: CGPoint(x: 352, y: 196), size: 11, color: Palette.blushDeep.withAlphaComponent(0.8))
        star(center: CGPoint(x: 92, y: 205), radius: 3.5, color: Palette.lavenderDeep)

        if let data = content.scrapbookImage, let art = UIImage(data: data) {
            let artWidth: CGFloat = 172
            let artHeight = artWidth * art.size.height / art.size.width
            art.draw(in: CGRect(x: (size.width - artWidth) / 2 - 30, y: 232 - artHeight, width: artWidth, height: artHeight))
        }
        if let data = content.cedImage, let ced = UIImage(data: data) {
            let cedWidth: CGFloat = 78
            let cedHeight = cedWidth * ced.size.height / ced.size.width
            ced.draw(in: CGRect(x: size.width / 2 + 40, y: 238 - cedHeight, width: cedWidth, height: cedHeight))
        }

        y = 282
        draw(Style.text("YOUR SCRAPBOOK", .eyebrow, Palette.accent, align: .center, kern: 2.4), after: 8)
        draw(Style.text("This chapter\nbelongs to you.", .coverTitle, Palette.foreground, align: .center), after: 12)
        if let dateRange = content.dateRange {
            draw(Style.text(dateRange, .body, Palette.muted, align: .center), after: 18)
        }
        // A small heart, then Ced's line.
        heart(center: CGPoint(x: size.width / 2, y: y + 4), size: 12, color: Palette.blushDeep)
        y += 18
        draw(Style.text("Gathered with care, by Ced.", .script, Palette.primary, align: .center), after: 0)
    }

    // MARK: Activities and memories (the heart of the book)

    func entries(_ entries: [ScrapbookContent.Entry]) {
        newPage()
        for (index, entry) in entries.enumerated() {
            let header = Style.text("\(entry.date.uppercased())  \u{B7}  \(entry.category.uppercased())", .eyebrow, Palette.accent, kern: 1.2)
            let title = Style.text(entry.title, .entryTitle, Palette.foreground)
            let caption = "\(entry.shortDate) \u{B7} \(entry.title)"
            let needed = height(header) + 4 + height(title) + 10 + memoryHeight(entry.memory, caption: caption)
            let opening = height(header) + 4 + height(title) + 10
                + (entry.memory?.photo != nil ? 240 : entry.memory?.note != nil ? 80 : 30)
            startBlock(needed: needed, opening: opening)
            draw(header, after: 4)
            draw(title, after: 10)
            if let memory = entry.memory {
                memoryBody(memory, caption: caption, index: index)
            }
            divider(after: 16)
        }
    }

    /// An activity starts on a fresh page when it would fit there whole but
    /// not in what's left of this one, so its photo and words stay together.
    /// One too tall for any page starts here (if its opening fits) and continues.
    private func startBlock(needed: CGFloat, opening: CGFloat) {
        guard needed > room, y > margin + 1 else { return }
        if needed <= bottom - margin || room < opening { newPage() }
    }

    func otherMemories(_ memories: [ScrapbookContent.Memory]) {
        // The heading moves with its first memory, so it's never alone on a page.
        section(eyebrow: "Moments", title: "More memories",
                keepWith: memories.first.map(otherMemoryHeight) ?? 140)
        for (index, memory) in memories.enumerated() {
            if index > 0 {
                startBlock(needed: otherMemoryHeight(memory), opening: memory.photo != nil ? 250 : 90)
            }
            draw(otherMemoryDate(memory), after: 8)
            memoryBody(memory, caption: memory.shortDate, index: index)
            divider(after: 16)
        }
    }

    private func otherMemoryDate(_ memory: ScrapbookContent.Memory) -> NSAttributedString {
        Style.text(memory.date.uppercased(), .eyebrow, Palette.accent, kern: 1.2)
    }

    private func otherMemoryHeight(_ memory: ScrapbookContent.Memory) -> CGFloat {
        height(otherMemoryDate(memory)) + 8 + memoryHeight(memory, caption: memory.shortDate)
    }

    private func memoryBody(_ memory: ScrapbookContent.Memory, caption: String, index: Int) {
        if let data = memory.photo, let photo = UIImage(data: data) {
            // Leave room under the photo for its words: all of them when they
            // fit on the page, otherwise their beginning (they continue overleaf).
            let words = memory.note.map { noteHeight($0) } ?? 0
            polaroid(photo, caption: caption, index: index, keepBelow: min(words, 110) + 2)
        } else if memory.photoNotIncluded {
            draw(Style.text("This photo couldn\u{2019}t be included.", .captionItalic, Palette.hint), after: 8)
        }
        if let note = memory.note {
            noteCard(label: Self.noteLabel, text: note,
                     fill: index % 2 == 0 ? Palette.lavender : Palette.blush)
        }
    }

    private static let noteLabel = "In your own words"

    /// How tall a memory will be: its Polaroid (or the missing-photo line),
    /// its reflection card and the divider after it.
    private func memoryHeight(_ memory: ScrapbookContent.Memory?, caption: String) -> CGFloat {
        guard let memory else { return 26 }
        var total: CGFloat = 26                          // divider
        if let data = memory.photo, let photo = UIImage(data: data) {
            total += polaroidLayout(photo, caption: caption).advance
        } else if memory.photoNotIncluded {
            total += 22
        }
        if let note = memory.note { total += noteHeight(note) }
        return total
    }

    /// The reflection card's full height, including the space after it.
    private func noteHeight(_ note: String) -> CGFloat {
        let pad: CGFloat = 12
        return pad + height(Style.text(Self.noteLabel, .label, Palette.primary)) + 4
            + height(Style.text(note, .body, Palette.foreground), width: width - pad * 2) + pad + 10
    }

    private struct PolaroidLayout {
        var imageWidth: CGFloat
        var imageHeight: CGFloat
        let frameWidth: CGFloat
        let captionHeight: CGFloat
        static let side: CGFloat = 10
        static let topSpace: CGFloat = 10                // the tape sits above the frame
        var bottomEdge: CGFloat { 10 + captionHeight + 10 }
        var frameHeight: CGFloat { Self.side + imageHeight + bottomEdge }
        var advance: CGFloat { Self.topSpace + frameHeight + 14 }
    }

    /// The Polaroid's natural size: at most 270 × 250 for the photo, never stretched.
    private func polaroidLayout(_ photo: UIImage, caption: String) -> PolaroidLayout {
        let aspect = photo.size.height / max(photo.size.width, 1)
        var imageWidth: CGFloat = 270
        var imageHeight = imageWidth * aspect
        if imageHeight > 250 {
            imageHeight = 250
            imageWidth = imageHeight / aspect
        }
        let frameWidth = max(imageWidth + PolaroidLayout.side * 2, 180)
        let captionText = Style.text(caption, .script, Palette.muted, align: .center)
        return PolaroidLayout(imageWidth: imageWidth, imageHeight: imageHeight, frameWidth: frameWidth,
                              captionHeight: height(captionText, width: frameWidth - PolaroidLayout.side * 2))
    }

    /// A Polaroid: white frame with a deeper bottom edge and a caption, a soft
    /// shadow, tape on top. The photo is never stretched; it shrinks to use
    /// the space left on the page when that's reasonable, instead of a gap.
    private func polaroid(_ photo: UIImage, caption: String, index: Int, keepBelow: CGFloat = 0) {
        let side = PolaroidLayout.side
        let topSpace = PolaroidLayout.topSpace
        let aspect = photo.size.height / max(photo.size.width, 1)
        var layout = polaroidLayout(photo, caption: caption)
        let captionText = Style.text(caption, .script, Palette.muted, align: .center)
        // Shrink (never stretch) to keep `keepBelow` free for the words that
        // follow; if even a 150 pt photo won't fit, it goes to the next page.
        if layout.advance + keepBelow > room {
            let available = min(layout.imageHeight, room - keepBelow - topSpace - side - layout.bottomEdge - 14)
            if available >= 150 {
                layout.imageHeight = available
                layout.imageWidth = available / aspect
            } else {
                newPage()
            }
        }
        let imageWidth = layout.imageWidth, imageHeight = layout.imageHeight
        let frameWidth = layout.frameWidth, frameHeight = layout.frameHeight, captionHeight = layout.captionHeight
        y += topSpace
        let frame = CGRect(x: margin + (width - frameWidth) / 2, y: y, width: frameWidth, height: frameHeight)
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: 2), blur: 6, color: UIColor.black.withAlphaComponent(0.12).cgColor)
        Palette.white.setFill()
        UIBezierPath(roundedRect: frame, cornerRadius: 2).fill()
        cg.restoreGState()
        let imageRect = CGRect(x: frame.midX - imageWidth / 2, y: frame.minY + side, width: imageWidth, height: imageHeight)
        photo.draw(in: imageRect)
        photoCorners(imageRect, color: Palette.white.withAlphaComponent(0.85))
        captionText.draw(with: CGRect(x: frame.minX + side, y: imageRect.maxY + 10, width: frameWidth - side * 2, height: captionHeight),
                         options: [.usesLineFragmentOrigin], context: nil)
        // Two strips of tape, alternating colours down the book.
        let tapeColor = index % 2 == 0 ? Palette.blush : Palette.paleBlueDeep
        tape(center: CGPoint(x: frame.minX + 16, y: frame.minY + 2), width: 46, angle: -0.6, color: tapeColor)
        tape(center: CGPoint(x: frame.maxX - 16, y: frame.minY + 2), width: 46, angle: 0.6, color: tapeColor)
        y = frame.maxY + 14
    }

    /// The user's own words on a little paper card, across pages if needed.
    private func noteCard(label: String, text: String, fill: UIColor) {
        let pad: CGFloat = 12
        let labelText = Style.text(label, .label, Palette.primary)
        let labelHeight = height(labelText)
        let body = Style.text(text, .body, Palette.foreground)
        // Room for all of it, or for its beginning when it's long.
        if room < min(noteHeight(text) - 10, pad * 2 + labelHeight + 40) { newPage() }
        let start = y
        var isFirstPart = true
        y += pad + labelHeight + 4
        // The card is drawn under each page's part, then the words on top.
        draw(body, indent: pad, trailing: pad, after: 0, reserveBelow: pad) { top, bottom in
            let cardTop = isFirstPart ? start : top - pad
            self.paperCard(CGRect(x: self.margin, y: cardTop, width: self.width, height: bottom + pad - cardTop), fill: fill)
            if isFirstPart {
                labelText.draw(with: CGRect(x: self.margin + pad, y: start + pad, width: self.width - pad * 2, height: labelHeight),
                               options: [.usesLineFragmentOrigin], context: nil)
                self.heart(center: CGPoint(x: self.margin + self.width - 16, y: start + pad + 6), size: 8,
                           color: Palette.blushDeep.withAlphaComponent(0.8))
                isFirstPart = false
            }
        }
        y += pad + 10
    }

    // MARK: Closing this chapter and Ced's letter

    /// A quiet page of its own: a small Ced, the heading, four short lines
    /// with room between them, and one soft heart.
    func closing(cedImage: Data?) {
        newPage()
        let ced = cedImage.flatMap(UIImage.init(data:))
        let cedWidth: CGFloat = 58
        let cedHeight = ced.map { cedWidth * $0.size.height / $0.size.width } ?? 0
        let heading = Style.text("Closing this chapter", .title, Palette.foreground, align: .center)
        let lines = ScrapbookPDF.closingLines.map { Style.text($0, .closing, Palette.foreground, align: .center) }
        let lineGap: CGFloat = 14
        let textWidth = width - 30
        let linesHeight = lines.reduce(0) { $0 + height($1, width: textWidth) } + lineGap * CGFloat(lines.count - 1)
        let total = cedHeight + 18 + height(heading) + 26 + linesHeight + 30 + 12
        // Balanced on the page, a touch above the middle.
        y = max(margin, (margin + bottom) / 2 - total / 2 - 20)

        if let ced {
            ced.draw(in: CGRect(x: (size.width - cedWidth) / 2, y: y, width: cedWidth, height: cedHeight))
            star(center: CGPoint(x: size.width / 2 - cedWidth / 2 - 14, y: y + 14), radius: 4, color: Palette.lavenderDeep)
            star(center: CGPoint(x: size.width / 2 + cedWidth / 2 + 12, y: y + 6), radius: 3, color: Palette.blushDeep.withAlphaComponent(0.7))
            y += cedHeight + 18
        }
        draw(heading, after: 26)
        for (index, line) in lines.enumerated() {
            let lineHeight = height(line, width: textWidth)
            line.draw(with: CGRect(x: margin + 15, y: y, width: textWidth, height: lineHeight),
                      options: [.usesLineFragmentOrigin], context: nil)
            y += lineHeight + (index < lines.count - 1 ? lineGap : 0)
        }
        heart(center: CGPoint(x: size.width / 2, y: y + 30), size: 12, color: Palette.blushDeep.withAlphaComponent(0.8))
        y += 42
    }

    func letter(cedImage: Data?, hasEntries: Bool) {
        newPage()
        draw(Style.text("A note from Ced", .title, Palette.foreground, align: .center), after: 18)

        let pad: CGFloat = 22
        let textWidth = width - pad * 2
        let paragraphs = ScrapbookPDF.letter(hasEntries: hasEntries).map { Style.text($0, .letter, Palette.foreground) }
        let closing = Style.text("With care,", .letter, Palette.foreground)
        let signature = Style.text("Ced", .signature, Palette.primary)
        let cedWidth: CGFloat = 48
        let ced = cedImage.flatMap(UIImage.init(data:))
        let cedHeight = ced.map { cedWidth * $0.size.height / $0.size.width } ?? 0
        let bodyHeight = paragraphs.reduce(0) { $0 + height($1, width: textWidth) + 12 }
        let closingHeight = height(closing, width: textWidth)
        let signatureHeight = height(signature, width: textWidth)
        let signatureBlock = max(closingHeight + 2 + signatureHeight, cedHeight)
        let card = CGRect(x: margin, y: y + 8, width: width, height: pad + bodyHeight + 6 + signatureBlock + pad)

        // A sheet of letter paper, taped on.
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: 2), blur: 6, color: UIColor.black.withAlphaComponent(0.08).cgColor)
        Palette.white.setFill()
        UIBezierPath(roundedRect: card, cornerRadius: 4).fill()
        cg.restoreGState()
        Palette.blush.setFill()
        UIRectFill(CGRect(x: card.minX, y: card.minY + 4, width: 4, height: card.height - 8))
        tape(center: CGPoint(x: card.midX, y: card.minY + 1), width: 70, angle: 0.03, color: Palette.lavenderDeep)

        var lineY = card.minY + pad
        for paragraph in paragraphs {
            let paragraphHeight = height(paragraph, width: textWidth)
            paragraph.draw(with: CGRect(x: card.minX + pad, y: lineY, width: textWidth, height: paragraphHeight),
                           options: [.usesLineFragmentOrigin], context: nil)
            lineY += paragraphHeight + 12
        }
        lineY += 6
        closing.draw(with: CGRect(x: card.minX + pad, y: lineY, width: textWidth, height: closingHeight),
                     options: [.usesLineFragmentOrigin], context: nil)
        signature.draw(with: CGRect(x: card.minX + pad, y: lineY + closingHeight + 2, width: textWidth, height: signatureHeight),
                       options: [.usesLineFragmentOrigin], context: nil)
        if let ced {
            ced.draw(in: CGRect(x: card.maxX - pad - cedWidth, y: card.maxY - pad - cedHeight, width: cedWidth, height: cedHeight))
            heart(center: CGPoint(x: card.maxX - pad - cedWidth - 10, y: card.maxY - pad - cedHeight + 10), size: 9,
                  color: Palette.blushDeep.withAlphaComponent(0.8))
        }
        y = card.maxY + 16
    }

    // MARK: Decorations

    func paperCard(_ rect: CGRect, fill: UIColor) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 10)
        fill.setFill()
        path.fill()
        Palette.border.withAlphaComponent(0.7).setStroke()
        path.lineWidth = 0.75
        path.stroke()
    }

    func tape(center: CGPoint, width tapeWidth: CGFloat, angle: CGFloat, color: UIColor) {
        cg.saveGState()
        cg.translateBy(x: center.x, y: center.y)
        cg.rotate(by: angle)
        color.withAlphaComponent(0.75).setFill()
        UIRectFill(CGRect(x: -tapeWidth / 2, y: -7, width: tapeWidth, height: 14))
        cg.restoreGState()
    }

    func photoCorners(_ rect: CGRect, color: UIColor) {
        let length: CGFloat = 14
        color.setFill()
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: rect.minX, y: rect.minY), 1, 1), (CGPoint(x: rect.maxX, y: rect.minY), -1, 1),
            (CGPoint(x: rect.minX, y: rect.maxY), 1, -1), (CGPoint(x: rect.maxX, y: rect.maxY), -1, -1),
        ]
        for (corner, dx, dy) in corners {
            let path = UIBezierPath()
            path.move(to: corner)
            path.addLine(to: CGPoint(x: corner.x + length * dx, y: corner.y))
            path.addLine(to: CGPoint(x: corner.x, y: corner.y + length * dy))
            path.close()
            path.fill()
        }
    }

    func heart(center: CGPoint, size s: CGFloat, color: UIColor) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: center.x, y: center.y + s * 0.45))
        path.addCurve(to: CGPoint(x: center.x - s * 0.5, y: center.y - s * 0.1),
                      controlPoint1: CGPoint(x: center.x - s * 0.15, y: center.y + s * 0.25),
                      controlPoint2: CGPoint(x: center.x - s * 0.5, y: center.y + s * 0.15))
        path.addArc(withCenter: CGPoint(x: center.x - s * 0.25, y: center.y - s * 0.12), radius: s * 0.25,
                    startAngle: .pi, endAngle: 0, clockwise: true)
        path.addArc(withCenter: CGPoint(x: center.x + s * 0.25, y: center.y - s * 0.12), radius: s * 0.25,
                    startAngle: .pi, endAngle: 0, clockwise: true)
        path.addCurve(to: CGPoint(x: center.x, y: center.y + s * 0.45),
                      controlPoint1: CGPoint(x: center.x + s * 0.5, y: center.y + s * 0.15),
                      controlPoint2: CGPoint(x: center.x + s * 0.15, y: center.y + s * 0.25))
        path.close()
        color.setFill()
        path.fill()
    }

    func star(center: CGPoint, radius: CGFloat, color: UIColor) {
        let path = UIBezierPath()
        for point in 0..<10 {
            let r = point % 2 == 0 ? radius : radius * 0.45
            let angle = CGFloat(point) * .pi / 5 - .pi / 2
            let p = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
            if point == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.close()
        color.setFill()
        path.fill()
    }

    // MARK: Text

    func height(_ text: NSAttributedString, width: CGFloat? = nil) -> CGFloat {
        ceil(text.boundingRect(with: CGSize(width: width ?? self.width, height: .greatestFiniteMagnitude),
                               options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
    }

    /// Draws text at `y`, continuing on the next page(s) when it doesn't fit,
    /// so long reflections are never cut off. `behind` draws under each
    /// page's part (given its top and bottom) before the text goes on top.
    func draw(_ text: NSAttributedString, indent: CGFloat = 0, trailing: CGFloat = 0, after spacing: CGFloat,
              reserveBelow: CGFloat = 0, behind: ((CGFloat, CGFloat) -> Void)? = nil) {
        var remaining = text
        let textWidth = width - indent - trailing
        while remaining.length > 0 {
            if room - reserveBelow < 20 { newPage() }
            let storage = NSTextStorage(attributedString: remaining)
            let layout = NSLayoutManager()
            let container = NSTextContainer(size: CGSize(width: textWidth, height: room - reserveBelow))
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            storage.addLayoutManager(layout)
            let glyphs = layout.glyphRange(for: container)
            let characters = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            guard characters.length > 0 else {
                if y <= margin { break }   // can't fit even on an empty page; give up safely
                newPage()
                continue
            }
            let used = ceil(layout.usedRect(for: container).height)
            behind?(y, y + used)
            layout.drawGlyphs(forGlyphRange: glyphs, at: CGPoint(x: margin + indent, y: y))
            y += used
            if characters.length >= remaining.length { break }
            remaining = remaining.attributedSubstring(
                from: NSRange(location: characters.length, length: remaining.length - characters.length))
            newPage()
        }
        y += spacing
    }

    func divider(after spacing: CGFloat) {
        guard room > 24 else { return }
        let center = CGPoint(x: margin + width / 2, y: y + 4)
        Palette.border.setFill()
        UIRectFill(CGRect(x: center.x - 60, y: center.y, width: 46, height: 1))
        UIRectFill(CGRect(x: center.x + 14, y: center.y, width: 46, height: 1))
        heart(center: center, size: 7, color: Palette.blushDeep.withAlphaComponent(0.6))
        y += 9 + spacing
    }
}

// MARK: - Look (the app's fonts and colours, plus soft paper accents)

private nonisolated enum Palette {
    static let paper = UIColor(hex: 0xFFFBF5)        // CEDColor.background (cream)
    static let white = UIColor.white
    static let foreground = UIColor(hex: 0x2D4052)
    static let muted = UIColor(hex: 0x596979)
    static let primary = UIColor(hex: 0x35677D)
    static let accent = UIColor(hex: 0x5A9CB5)
    static let border = UIColor(hex: 0xD5E2E8)
    static let hint = UIColor(hex: 0x8FAABB)
    static let sunrise = UIColor(hex: 0xE8A030)      // CEDColor.sunriseAmber
    static let paleBlue = UIColor(hex: 0xE7F1F6)     // CEDColor.secondary
    static let paleBlueDeep = UIColor(hex: 0xC9DFEA)
    static let lavender = UIColor(hex: 0xF0EEFF)     // Ced's own body colour
    static let lavenderDeep = UIColor(hex: 0xD9D3F2)
    static let blush = UIColor(hex: 0xF8E3E7)        // from the scrapbook's pinks
    static let blushDeep = UIColor(hex: 0xE8A0B0)

}

private nonisolated enum Style {
    enum Kind {
        case coverTitle, title, entryTitle, closing, eyebrow, label, body, letter,
             caption, captionItalic, script, signature, small

        var font: UIFont {
            switch self {
            case .coverTitle: font("Lora-Bold", 30)
            case .title: font("Lora-Bold", 20)
            case .entryTitle: font("Lora-SemiBold", 15)
            case .closing: font("Nunito-Regular", 13)
            case .eyebrow: font("Nunito-Bold", 8.5)
            case .label: font("Lora-SemiBold", 11)
            case .body: font("Nunito-Regular", 11)
            case .letter: font("Nunito-Regular", 11.5)
            case .caption: font("Nunito-Regular", 10)
            case .captionItalic: font("Lora-Italic", 10)
            case .script: font("Lora-Italic", 11.5)
            case .signature: font("Lora-MediumItalic", 22)
            case .small: font("Nunito-Regular", 8)
            }
        }

        var lineSpacing: CGFloat {
            switch self {
            case .body, .letter, .closing: 3.5
            case .coverTitle: 2
            default: 1.5
            }
        }

        private func font(_ name: String, _ size: CGFloat) -> UIFont {
            UIFont(name: name, size: size) ?? .systemFont(ofSize: size)
        }
    }

    static func text(_ string: String, _ kind: Kind, _ color: UIColor,
                     align: NSTextAlignment = .natural, kern: CGFloat = 0) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = kind.lineSpacing
        paragraph.alignment = align
        paragraph.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: string, attributes: [
            .font: kind.font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
            .kern: kern,
        ])
    }
}

private nonisolated extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
