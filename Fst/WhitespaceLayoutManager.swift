import AppKit

final class WhitespaceLayoutManager: NSLayoutManager {
    var showWhitespace = false {
        didSet {
            guard showWhitespace != oldValue else { return }
            for container in textContainers {
                container.textView?.needsDisplay = true
            }
        }
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard showWhitespace, glyphsToShow.length > 0, let textStorage,
              let container = textContainer(forGlyphAt: glyphsToShow.location, effectiveRange: nil),
              let textView = container.textView, let font = textView.font,
              let color = textView.textColor else { return }

        let text = textStorage.mutableString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color.withAlphaComponent(color.alphaComponent * 0.35)
        ]
        let dot = "·" as NSString
        let arrow = "→" as NSString
        let dotSize = dot.size(withAttributes: attributes)
        let arrowSize = arrow.size(withAttributes: attributes)
        let baseline = defaultBaselineOffset(for: font)

        enumerateLineFragments(forGlyphRange: glyphsToShow) { fragment, _, _, lineGlyphs, _ in
            let range = NSIntersectionRange(glyphsToShow, lineGlyphs)
            let truncated = self.truncatedGlyphRange(inLineFragmentForGlyphAt: range.location)
            for glyph in range.location..<NSMaxRange(range) {
                let character = text.character(at: self.characterIndexForGlyph(at: glyph))
                guard character == 0x20 || character == 0x09 else { continue }
                guard !NSLocationInRange(glyph, truncated) else { continue }

                let location = self.location(forGlyphAt: glyph)
                let cell = self.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1),
                                             in: container).offsetBy(dx: origin.x, dy: origin.y)
                guard cell.width > 0, cell.intersects(textView.visibleRect) else { continue }
                let marker = character == 0x20 ? dot : arrow
                let size = character == 0x20 ? dotSize : arrowSize
                let point = NSPoint(x: cell.midX - size.width / 2,
                                    y: origin.y + fragment.minY + location.y - baseline)
                NSGraphicsContext.saveGraphicsState()
                cell.clip()
                marker.draw(at: point, withAttributes: attributes)
                NSGraphicsContext.restoreGraphicsState()
            }
        }
    }
}
