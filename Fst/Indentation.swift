import Foundation

struct Indentation: Equatable {
    var size: Int
    var spaces: Bool

    static func detect(_ source: NSString) -> (spaces: Bool, size: Int?)? {
        // ponytail: sample 64 KiB/1000 lines; explicit per-file selection handles ambiguous files.
        let limit = min(source.length, 65_536)
        var offset = 0, lines = 0, spaceLines = 0, tabLines = 0, previous = 0
        var votes = [Int: Int]()
        while offset < limit && lines < 1000 {
            var width = 0, hasTab = false
            while offset < limit {
                let c = source.character(at: offset)
                if c == 32 { width += 1 }
                else if c == 9 { hasTab = true }
                else { break }
                offset += 1
            }
            guard offset < limit else { break }
            let c = source.character(at: offset)
            if c != 10 && c != 13 {
                if hasTab { tabLines += 1; previous = 0 }
                else {
                    if width > 0 { spaceLines += 1 }
                    let delta = abs(width - previous)
                    if (1...8).contains(delta) { votes[delta, default: 0] += 1 }
                    previous = width
                }
            }
            while offset < limit && source.character(at: offset) != 10 && source.character(at: offset) != 13 { offset += 1 }
            if offset < limit {
                let newline = source.character(at: offset)
                offset += 1
                if newline == 13 && offset < limit && source.character(at: offset) == 10 { offset += 1 }
            }
            lines += 1
        }
        if tabLines > spaceLines { return (false, nil) }
        guard spaceLines > tabLines,
              let winner = votes.max(by: { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }),
              winner.value >= 2 else { return nil }
        return (true, winner.key)
    }

    func column(in source: NSString, range: NSRange) -> Int {
        var column = 0
        for index in range.location..<NSMaxRange(range) {
            column += source.character(at: index) == 9 ? size - column % size : 1
        }
        return column
    }
}
