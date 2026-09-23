import AppKit

final class CodeTextView: NSTextView {
    var newline = "\n"
    var indentation = Indentation(size: 4, spaces: true)

    override func insertTab(_ sender: Any?) {
        guard indentation.spaces else { super.insertTab(sender); return }
        let source = string as NSString
        let selection = selectedRange()
        let start = source.lineRange(for: NSRange(location: selection.location, length: 0)).location
        let column = indentation.column(in: source, range: NSRange(location: start, length: selection.location - start))
        insertText(String(repeating: " ", count: indentation.size - column % indentation.size), replacementRange: selection)
    }

    override func deleteBackward(_ sender: Any?) {
        let selection = selectedRange()
        guard indentation.spaces, selection.length == 0, selection.location > 0 else {
            super.deleteBackward(sender); return
        }
        let source = string as NSString
        let start = source.lineRange(for: NSRange(location: selection.location, length: 0)).location
        let prefix = source.substring(with: NSRange(location: start, length: selection.location - start))
        guard !prefix.isEmpty, prefix.allSatisfy({ $0 == " " }) else { super.deleteBackward(sender); return }
        let count = (prefix.count - 1) % indentation.size + 1
        insertText("", replacementRange: NSRange(location: selection.location - count, length: count))
    }
    var appearanceChanged: (() -> Void)?
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        appearanceChanged?()
    }

    override func mouseDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let point = convert(event.locationInWindow, from: nil)
        guard event.clickCount == 1, modifiers.isEmpty, isBelowText(point) else {
            super.mouseDown(with: event)
            return
        }

        window?.makeFirstResponder(self)
        setSelectedRange(NSRange(location: textStorage?.length ?? 0, length: 0),
                         affinity: .downstream, stillSelecting: false)
    }

    private func isBelowText(_ point: NSPoint) -> Bool {
        guard let layoutManager, let textContainer else { return false }
        layoutManager.ensureLayout(for: textContainer)
        let bottom = max(layoutManager.usedRect(for: textContainer).maxY,
                         layoutManager.extraLineFragmentRect.maxY) + textContainerOrigin.y
        return point.y > bottom
    }

    override func insertNewline(_ sender: Any?) {
        let source = textStorage?.mutableString ?? (string as NSString)
        let location = selectedRange().location
        let line = source.lineRange(for: NSRange(location: location, length: 0))
        let prefix = source.substring(with: NSRange(location: line.location, length: location - line.location))
        var indentation = String(prefix.prefix { $0 == " " || $0 == "\t" })
        if self.indentation.spaces {
            let width = self.indentation.column(in: indentation as NSString, range: NSRange(location: 0, length: (indentation as NSString).length))
            indentation = String(repeating: " ", count: width)
        }
        insertText(newline + indentation, replacementRange: selectedRange())
    }
}

final class EditorViewController: NSViewController, NSTextViewDelegate {
    let textView = CodeTextView(frame: .zero)
    private(set) var highlighter: SyntaxHighlighter!
    let lineIndex = LineIndex()
    private var ruler: LineNumberRuler!
    private let positionLabel = NSTextField(labelWithString: "Ln 1, Col 1")
    private let detailsLabel = NSTextField(labelWithString: "UTF-8 · LF · 1 line")
    let languagePicker = NSPopUpButton()
    let indentPicker = NSPopUpButton()
    private let convertButton = NSButton(title: "Tabs → Spaces", target: nil, action: nil)
    private var detectedIndentation: (spaces: Bool, size: Int?)?
    private var manualIndentation: Indentation?
    private var filename = ""
    private var languageOverride: String?
    private var replacingText = false
    var encodingName = "UTF-8" { didSet { updateStatus() } }
    private var themeObserver: NSObjectProtocol?
    private static var reportedLaunch = false

    override func loadView() {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.clipsToBounds = true
        scroll.setContentHuggingPriority(.fittingSizeCompression, for: .vertical)
        scroll.setContentHuggingPriority(.fittingSizeCompression, for: .horizontal)
        textView.textContainer?.replaceLayoutManager(WhitespaceLayoutManager())
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textContainerInset = NSSize(width: 20, height: 18)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.layoutManager?.allowsNonContiguousLayout = true
        scroll.documentView = textView
        textView.delegate = self
        ruler = LineNumberRuler(scrollView: scroll, textView: textView, index: lineIndex)
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        languagePicker.addItem(withTitle: "Automatic — Plain Text")
        languagePicker.addItems(withTitles: LanguageMode.all.map(\.name))
        languagePicker.target = self
        languagePicker.action = #selector(changeLanguage(_:))
        languagePicker.controlSize = .small
        languagePicker.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        languagePicker.isBordered = false
        languagePicker.setAccessibilityLabel("Syntax language")
        indentPicker.target = self
        indentPicker.action = #selector(changeIndentation(_:))
        indentPicker.controlSize = .small
        indentPicker.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        indentPicker.isBordered = false
        indentPicker.setAccessibilityLabel("Indentation")
        convertButton.target = self
        convertButton.action = #selector(convertTabsToSpaces(_:))
        convertButton.controlSize = .small
        convertButton.bezelStyle = .rounded
        convertButton.toolTip = "Convert leading tabs to spaces using this file’s indent size. Undoable."
        positionLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        positionLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        detailsLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        detailsLabel.lineBreakMode = .byTruncatingHead
        positionLabel.textColor = .secondaryLabelColor
        detailsLabel.textColor = .secondaryLabelColor
        let spacer = NSView()
        let status = NSStackView(views: [positionLabel, spacer, detailsLabel, indentPicker, convertButton, languagePicker])
        status.setVisibilityPriority(NSStackView.VisibilityPriority(rawValue: 900), for: detailsLabel)
        status.setVisibilityPriority(NSStackView.VisibilityPriority(rawValue: 800), for: languagePicker)
        status.setVisibilityPriority(NSStackView.VisibilityPriority(rawValue: 700), for: positionLabel)
        status.orientation = .horizontal
        status.setContentHuggingPriority(.fittingSizeCompression, for: .horizontal)
        status.setClippingResistancePriority(.defaultLow, for: .horizontal)
        status.spacing = 12
        status.edgeInsets = NSEdgeInsets(top: 4, left: 12, bottom: 4, right: 8)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        status.translatesAutoresizingMaskIntoConstraints = false
        view = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 680))
        view.addSubview(scroll)
        view.addSubview(status)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 240),
            scroll.topAnchor.constraint(equalTo: view.topAnchor), scroll.bottomAnchor.constraint(equalTo: status.topAnchor),
            status.leadingAnchor.constraint(equalTo: view.leadingAnchor), status.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            status.bottomAnchor.constraint(equalTo: view.bottomAnchor), status.heightAnchor.constraint(equalToConstant: 30)
        ])
        highlighter = SyntaxHighlighter(textView: textView)
        highlighter.onEdit = { [weak self] storage, range, delta in
            guard let self, !self.replacingText else { return }
            self.lineIndex.update(storage.mutableString, editedRange: range, delta: delta)
            self.ruler.refresh()
        }
        textView.appearanceChanged = { [weak self] in self?.applyTheme() }
        themeObserver = NotificationCenter.default.addObserver(forName: .editorPreferencesChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyPreferences() }
        }
        applyPreferences()
    }

    deinit { if let themeObserver { NotificationCenter.default.removeObserver(themeObserver) } }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard !Self.reportedLaunch else { return }
        Self.reportedLaunch = true
        // Opt-in benchmark output; never touches disk during ordinary startup.
        if let path = ProcessInfo.processInfo.environment["FST_LAUNCH_REPORT"] {
            view.window?.displayIfNeeded()
            let elapsed = ProcessInfo.processInfo.systemUptime - Performance.launchStarted
            try? String(format: "%.4f\n", elapsed).write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    func setText(_ text: String, filename: String) {
        replacingText = true
        let source = text as NSString
        manualIndentation = nil
        detectedIndentation = EditorPreferences.detectIndentation ? Indentation.detect(source) : nil
        textView.newline = source.range(of: "\r\n").location != NSNotFound ? "\r\n"
            : (source.range(of: "\r").location != NSNotFound && source.range(of: "\n").location == NSNotFound ? "\r" : "\n")
        textView.string = text
        lineIndex.rebuild(textView.textStorage!.mutableString)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        replacingText = false
        textView.undoManager?.removeAllActions()
        setLanguage(filename: filename)
        applyIndentation()
        applyTypography()
        ruler.refresh()
        updateStatus()
    }

    func setLanguage(filename: String) {
        self.filename = filename
        languagePicker.item(at: 0)?.title = "Automatic — " + LanguageMode.detectedName(filename)
        highlighter?.setLanguage(filename: languageOverride ?? filename)
    }

    @objc func changeLanguage(_ sender: NSPopUpButton) {
        languageOverride = sender.indexOfSelectedItem == 0 ? nil : LanguageMode.all[sender.indexOfSelectedItem - 1].filename
        highlighter.setLanguage(filename: languageOverride ?? filename)
    }

    @objc func changeIndentation(_ sender: NSPopUpButton) {
        if sender.selectedTag() == 0 {
            manualIndentation = nil
            detectedIndentation = EditorPreferences.detectIndentation ? Indentation.detect(textView.string as NSString) : nil
        } else {
            let tag = sender.selectedTag()
            manualIndentation = Indentation(size: tag % 10, spaces: tag < 20)
        }
        applyIndentation()
        applyTypography()
    }

    private func applyIndentation() {
        let detected = EditorPreferences.detectIndentation ? detectedIndentation : nil
        textView.indentation = manualIndentation ?? Indentation(size: detected?.size ?? EditorPreferences.indentSize,
                                                               spaces: detected?.spaces ?? EditorPreferences.insertSpaces)
        let current = textView.indentation
        let origin = manualIndentation != nil ? "manual" : (detected != nil ? "detected" : "default")
        indentPicker.removeAllItems()
        indentPicker.addItem(withTitle: "\(current.spaces ? "Spaces" : "Tabs"): \(current.size) (\(origin))")
        indentPicker.lastItem?.tag = -1
        indentPicker.lastItem?.isEnabled = false
        indentPicker.addItem(withTitle: "Automatic")
        indentPicker.lastItem?.tag = 0
        for spaces in [true, false] {
            for size in 1...8 {
                indentPicker.addItem(withTitle: "\(spaces ? "Spaces" : "Tabs"): \(size)")
                indentPicker.lastItem?.tag = (spaces ? 10 : 20) + size
            }
        }
        indentPicker.selectItem(at: 0)
    }

    @objc func convertTabsToSpaces(_ sender: Any?) {
        let source = textView.string as NSString
        var ranges = [NSRange](), replacements = [String]()
        var offset = 0
        while offset < source.length {
            let line = source.lineRange(for: NSRange(location: offset, length: 0))
            var column = 0
            while offset < NSMaxRange(line) {
                let character = source.character(at: offset)
                if character == 9 {
                    let count = textView.indentation.size - column % textView.indentation.size
                    ranges.append(NSRange(location: offset, length: 1))
                    replacements.append(String(repeating: " ", count: count))
                    column += count
                } else if character == 32 { column += 1 }
                else { break }
                offset += 1
            }
            offset = NSMaxRange(line)
        }
        guard !ranges.isEmpty else { return }
        textView.breakUndoCoalescing()
        guard textView.shouldChangeText(inRanges: ranges.map { NSValue(range: $0) }, replacementStrings: replacements) else { return }
        let selections = textView.selectedRanges.map { $0.rangeValue }
        func mapped(_ position: Int) -> Int {
            position + zip(ranges, replacements).reduce(0) { result, edit in
                result + (edit.0.location < position ? edit.1.utf16.count - 1 : 0)
            }
        }
        textView.textStorage?.beginEditing()
        for (range, replacement) in zip(ranges, replacements).reversed() {
            textView.textStorage?.replaceCharacters(in: range, with: replacement)
        }
        textView.textStorage?.endEditing()
        textView.didChangeText()
        textView.undoManager?.setActionName("Convert Tabs to Spaces")
        textView.selectedRanges = selections.map {
            NSValue(range: NSRange(location: mapped($0.location), length: mapped(NSMaxRange($0)) - mapped($0.location)))
        }
        manualIndentation = Indentation(size: textView.indentation.size, spaces: true)
        applyIndentation()
        applyTypography()
    }

    func textViewDidChangeSelection(_ notification: Notification) { updateStatus() }
    func textDidChange(_ notification: Notification) { updateStatus() }

    private func updateStatus() {
        guard isViewLoaded else { return }
        let source = textView.textStorage!.mutableString
        let offset = min(textView.selectedRange().location, source.length)
        let line = lineIndex.line(at: offset)
        // Columns count UTF-16 code units, matching TextKit selections.
        positionLabel.stringValue = "Ln \(line + 1), Col \(offset - lineIndex.starts[line] + 1)"
        positionLabel.toolTip = "Columns count UTF-16 code units; tabs count as one."
        let endings = textView.newline == "\r\n" ? "CRLF" : (textView.newline == "\r" ? "CR" : "LF")
        detailsLabel.stringValue = "\(encodingName) · \(endings) · \(lineIndex.count.formatted()) \(lineIndex.count == 1 ? "line" : "lines")"
        ruler?.needsDisplay = true
    }

    private func applyPreferences() {
        applyWrapping()
        textView.enclosingScrollView?.rulersVisible = EditorPreferences.showLineNumbers
        (textView.layoutManager as? WhitespaceLayoutManager)?.showWhitespace = EditorPreferences.showWhitespace
        if EditorPreferences.detectIndentation && detectedIndentation == nil {
            detectedIndentation = Indentation.detect(textView.string as NSString)
        }
        applyIndentation()
        applyTypography()
        applyTheme()
        ruler.refresh()
    }

    private func applyWrapping() {
        guard let container = textView.textContainer, let scroll = textView.enclosingScrollView else { return }
        let wraps = EditorPreferences.wrapLines
        guard container.widthTracksTextView != wraps else { return }
        textView.isHorizontallyResizable = !wraps
        container.widthTracksTextView = wraps
        scroll.hasHorizontalScroller = !wraps
        if wraps {
            textView.setFrameSize(NSSize(width: scroll.contentSize.width, height: textView.frame.height))
            container.containerSize = NSSize(width: max(0, scroll.contentSize.width - 2 * textView.textContainerInset.width),
                                             height: CGFloat.greatestFiniteMagnitude)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: scroll.contentView.bounds.minY))
            scroll.reflectScrolledClipView(scroll.contentView)
        } else {
            container.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
        textView.needsDisplay = true
    }

    private func applyTypography() {
        let paragraph = EditorPreferences.paragraphStyle.mutableCopy() as! NSMutableParagraphStyle
        paragraph.defaultTabInterval = (" " as NSString).size(withAttributes: [.font: EditorPreferences.font]).width * CGFloat(textView.indentation.size)
        textView.font = EditorPreferences.font
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes[.font] = EditorPreferences.font
        textView.typingAttributes[.paragraphStyle] = paragraph
        if let storage = textView.textStorage, storage.length > 0 {
            storage.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: storage.length))
        }
    }

    private func applyTheme() {
        let theme = EditorTheme.current(for: textView.effectiveAppearance)
        textView.backgroundColor = theme.background
        textView.textColor = theme.foreground
        textView.typingAttributes[.foregroundColor] = theme.foreground
        if let storage = textView.textStorage, storage.length > 0 {
            storage.addAttribute(.foregroundColor, value: theme.foreground,
                                 range: NSRange(location: 0, length: storage.length))
        }
        textView.insertionPointColor = theme.caret ?? theme.foreground
        textView.selectedTextAttributes = [.backgroundColor: theme.selection ?? NSColor.selectedTextBackgroundColor]
        highlighter?.theme = theme
        ruler?.needsDisplay = true
    }
}
