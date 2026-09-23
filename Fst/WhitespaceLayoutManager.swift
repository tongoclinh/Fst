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

    var showIndentGuides = true {
        didSet { if showIndentGuides != oldValue { invalidateGuideDisplay() } }
    }
    var highlightActiveIndentGuide = true {
        didSet { if highlightActiveIndentGuide != oldValue { invalidateGuideDisplay() } }
    }

    private(set) var guideIndex: IndentGuideIndex?
    private(set) var activeGuideBlock: IndentGuideIndex.Block?
    private var guideSelectionOffset = 0

    func setGuides(_ index: IndentGuideIndex?) {
        guideIndex = index
        activeGuideBlock = guideIndex?.activeBlock(atCharacterOffset: guideSelectionOffset)
        invalidateGuideDisplay()
    }

    func updateGuideSelection(characterOffset: Int) {
        guideSelectionOffset = characterOffset
        let block = guideIndex?.activeBlock(atCharacterOffset: characterOffset)
        guard block != activeGuideBlock else { return }
        activeGuideBlock = block
        if highlightActiveIndentGuide { invalidateGuideDisplay() }
    }

    private func invalidateGuideDisplay() {
        for container in textContainers { container.textView?.needsDisplay = true }
    }

    private func drawIndentGuides(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard showIndentGuides, glyphsToShow.length > 0, let guideIndex,
              let container = textContainer(forGlyphAt: glyphsToShow.location, effectiveRange: nil),
              let textView = container.textView, let font = textView.font,
              let color = textView.textColor else { return }
        let visible = textView.visibleRect
        let visibleGlyphs = glyphRange(forBoundingRect: visible.offsetBy(dx: -origin.x, dy: -origin.y),
                                      in: container)
        let glyphs = NSIntersectionRange(glyphsToShow, visibleGlyphs)
        guard glyphs.length > 0 else { return }
        let width = (" " as NSString).size(withAttributes: [.font: font]).width
        guard width > 0 else { return }
        let scale = textView.window?.backingScaleFactor ?? 1
        let muted = NSBezierPath()
        let active = NSBezierPath()
        muted.lineWidth = 1 / scale
        active.lineWidth = 1 / scale
        let selected = highlightActiveIndentGuide ? activeGuideBlock : nil

        enumerateLineFragments(forGlyphRange: glyphs) { fragment, _, _, lineGlyphs, _ in
            let character = self.characterIndexForGlyph(at: lineGlyphs.location)
            let number = guideIndex.line(atCharacterOffset: character)
            // A wrapped continuation is text, not a new indentation margin.
            guard character == guideIndex.starts[number] else { return }
            let line = guideIndex.lines[number]
            let baseX = origin.x + fragment.minX + self.location(forGlyphAt: lineGlyphs.location).x
            let minY = max(visible.minY, origin.y + fragment.minY)
            let maxY = min(visible.maxY, origin.y + fragment.maxY)
            guard maxY > minY else { return }
            let maxX = min(visible.maxX, origin.x + fragment.maxX - container.lineFragmentPadding)
            let activeColumn: Int? = selected.flatMap { block in
                guard number > block.openerLine, number <= block.endLine,
                      block.column < line.guideColumnLimit || block.column == line.bridgingColumn else { return nil }
                return block.column
            }
            func appendGuide(column: Int, to path: NSBezierPath) {
                let x = (baseX + CGFloat(column) * width) * scale
                let alignedX = (floor(x) + 0.5) / scale
                guard alignedX >= visible.minX, alignedX < maxX else { return }
                path.move(to: NSPoint(x: alignedX, y: minY))
                path.line(to: NSPoint(x: alignedX, y: maxY))
            }
            // Clamp columns before iterating, including when a huge indent wraps.
            let firstColumn = max(0, Int(floor((visible.minX - baseX) / width / CGFloat(guideIndex.indentSize))))
                * guideIndex.indentSize
            let lastColumn = min(line.guideColumnLimit, max(0, Int(ceil((maxX - baseX) / width))))
            if firstColumn < lastColumn {
                for column in stride(from: firstColumn, to: lastColumn, by: guideIndex.indentSize) {
                    if column != activeColumn { appendGuide(column: column, to: muted) }
                }
            }
            if let column = line.bridgingColumn, column != activeColumn {
                appendGuide(column: column, to: muted)
            }
            if let activeColumn { appendGuide(column: activeColumn, to: active) }
        }
        NSGraphicsContext.saveGraphicsState()
        visible.clip()
        color.withAlphaComponent(color.alphaComponent * 0.14).setStroke()
        muted.stroke()
        color.withAlphaComponent(color.alphaComponent * 0.5).setStroke()
        active.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        drawIndentGuides(forGlyphRange: glyphsToShow, at: origin)
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
