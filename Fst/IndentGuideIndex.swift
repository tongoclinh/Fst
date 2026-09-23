import Foundation

/// Indentation-only structure. All offsets are UTF-16; columns expand tabs to the next stop.
struct IndentGuideIndex {
    struct Line {
        let indentationColumn: Int
        let contentOffset: Int
        let isBlank: Bool
        var guideColumnLimit: Int
        var bridgingColumn: Int?
        var activeBlockIndex: Int?
    }

    struct Block: Equatable {
        let openerLine: Int
        var endLine: Int
        let column: Int
    }

    let starts: [Int]
    let sourceLength: Int
    let indentSize: Int
    private(set) var lines: [Line]
    private(set) var blocks: [Block] = []

    init(source: NSString, starts: [Int], indentation: Indentation) {
        self.starts = starts
        sourceLength = source.length
        indentSize = max(1, indentation.size)
        let indentation = Indentation(size: indentSize, spaces: indentation.spaces)
        lines = starts.enumerated().map { number, start in
            let end = number + 1 < starts.count ? starts[number + 1] : source.length
            var offset = start
            while offset < end {
                let character = source.character(at: offset)
                guard character == 0x20 || character == 0x09 else { break }
                offset += 1
            }
            let column = indentation.column(in: source, range: NSRange(location: start, length: offset - start))
            let character = offset < end ? source.character(at: offset) : 0x0A
            let blank = character == 0x0A || character == 0x0D || character == 0x85
                || character == 0x2028 || character == 0x2029
            return Line(indentationColumn: column, contentOffset: offset, isBlank: blank,
                        guideColumnLimit: blank ? 0 : column)
        }

        var stack: [Int] = []
        var previous: Int?
        for line in lines.indices where !lines[line].isBlank {
            let column = lines[line].indentationColumn
            while let block = stack.last, blocks[block].column >= column {
                blocks[block].endLine = previous ?? blocks[block].openerLine
                stack.removeLast()
            }
            if let previous {
                let previousColumn = lines[previous].indentationColumn
                let opensBlock = column > previousColumn
                if opensBlock {
                    let block = blocks.count
                    blocks.append(Block(openerLine: previous, endLine: line, column: previousColumn))
                    stack.append(block)
                    lines[previous].activeBlockIndex = block
                }
                // Blank runs share the surviving block, never the block that just ended.
                for blank in (previous + 1)..<line {
                    lines[blank].guideColumnLimit = min(previousColumn, column)
                    lines[blank].bridgingColumn = opensBlock ? previousColumn : nil
                    lines[blank].activeBlockIndex = stack.last
                }
            }
            lines[line].activeBlockIndex = stack.last
            previous = line
        }
        if let previous {
            for block in stack { blocks[block].endLine = previous }
        }
        // Leading/trailing blank lines deliberately retain no guides or active block.
    }

    func line(atCharacterOffset offset: Int) -> Int {
        let offset = min(max(0, offset), sourceLength)
        var low = 0, high = starts.count
        while low < high {
            let middle = (low + high) / 2
            if starts[middle] <= offset { low = middle + 1 } else { high = middle }
        }
        return max(0, low - 1)
    }

    func activeBlock(atCharacterOffset offset: Int) -> Block? {
        guard let block = lines[line(atCharacterOffset: offset)].activeBlockIndex else { return nil }
        return blocks[block]
    }
}
