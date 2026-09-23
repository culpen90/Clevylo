import Foundation
import CryptoKit

/// A local, immutable snapshot. Rebuild after library changes so deleted and edited
/// content cannot remain in retrieval or resolve through old saved citations.
struct SourceIndex {
    private struct Passage {
        var reference: SourceReference
        var frequencies: [String: Int]
        var titleTerms: Set<String>
        var wordCount: Int
        var sourceOrder: Int
        var passageOrder: Int
    }
    private let passages: [Passage]
    private let byIdentity: [String: SourceReference]

    init(library: Library) {
        var indexed: [Passage] = []
        var sourceOrder = 0
        func append(_ text: String, title: String, page: Int?, materialID: UUID? = nil,
                    noteID: UUID? = nil, assignmentID: UUID? = nil, startingAt: Int = 0) -> Int {
            let chunks = Self.chunks(text)
            for (offset, excerpt) in chunks.enumerated() {
                let parent = materialID ?? noteID ?? assignmentID!
                let type = materialID != nil ? "material" : noteID != nil ? "note" : "assignment"
                let identityInput = "\(type):\(parent.uuidString):\(page ?? 0):\(offset):\(excerpt)"
                let identity = SHA256.hash(data: Data(identityInput.utf8)).map { String(format: "%02x", $0) }.joined()
                let reference = SourceReference(id: "", materialID: materialID, noteID: noteID,
                                                assignmentID: assignmentID, title: title, page: page,
                                                excerpt: excerpt, passageID: identity)
                let terms = Self.terms(excerpt)
                var frequencies: [String: Int] = [:]
                for term in terms { frequencies[term, default: 0] += 1 }
                indexed.append(Passage(reference: reference, frequencies: frequencies,
                                       titleTerms: Set(Self.terms(title)), wordCount: terms.count,
                                       sourceOrder: sourceOrder, passageOrder: startingAt + offset))
            }
            return chunks.count
        }
        for material in library.materials {
            var offset = 0
            for page in material.pages {
                offset += append(page.text, title: material.name, page: page.number,
                                 materialID: material.id, startingAt: offset)
            }
            sourceOrder += 1
        }
        for note in library.notes {
            _ = append(note.text, title: note.title, page: nil, noteID: note.id)
            sourceOrder += 1
        }
        for assignment in library.assignments {
            let content = assignment.title + (assignment.instructions.isEmpty ? "" : "\n" + assignment.instructions)
            _ = append(content, title: assignment.title, page: nil, assignmentID: assignment.id)
            sourceOrder += 1
        }
        passages = indexed
        // Duplicate or corrupt imported identifiers must not crash the library.
        byIdentity = Dictionary(indexed.map { ($0.reference.passageID!, $0.reference) }, uniquingKeysWith: { first, _ in first })
    }

    func retrieve(query: String, materialIDs: Set<UUID>, noteIDs: Set<UUID>,
                  assignmentIDs: Set<UUID>, limit: Int = 8) -> [SourceReference] {
        guard limit > 0 else { return [] }
        let eligible = passages.filter { passage in
            let source = passage.reference
            return source.materialID.map { materialIDs.contains($0) } == true
                || source.noteID.map { noteIDs.contains($0) } == true
                || source.assignmentID.map { assignmentIDs.contains($0) } == true
        }
        guard !eligible.isEmpty else { return [] }
        let queryTerms = Set(Self.terms(query)).subtracting(Self.stopWords)
        let meanLength = Double(eligible.reduce(0) { $0 + $1.wordCount }) / Double(eligible.count)
        var documentFrequency: [String: Int] = [:]
        for passage in eligible {
            for term in queryTerms where passage.frequencies[term] != nil {
                documentFrequency[term, default: 0] += 1
            }
        }
        let scored = eligible.map { passage -> (Passage, Double) in
            var score = 0.0
            for term in queryTerms {
                if let frequency = passage.frequencies[term] {
                    let df = Double(documentFrequency[term, default: 0])
                    let inverseFrequency = log(1 + (Double(eligible.count) - df + 0.5) / (df + 0.5))
                    let lengthAdjustment = 1.2 * (0.25 + 0.75 * Double(passage.wordCount) / max(1, meanLength))
                    score += inverseFrequency * Double(frequency) * 2.2 / (Double(frequency) + lengthAdjustment)
                }
                if passage.titleTerms.contains(term) { score += 0.4 }
            }
            return (passage, score)
        }
        let hasMatches = scored.contains { $0.1 > 0 }
        let ranked = scored.filter { !hasMatches || $0.1 > 0 }.sorted { left, right in
            if left.1 != right.1 { return left.1 > right.1 }
            // A general "explain this" request gets a representative first passage
            // from each explicitly chosen source before additional passages.
            if left.0.passageOrder != right.0.passageOrder { return left.0.passageOrder < right.0.passageOrder }
            return left.0.sourceOrder < right.0.sourceOrder
        }
        return ranked.prefix(min(limit, 24)).enumerated().map { index, entry in
            var reference = entry.0.reference
            reference.id = "S\(index + 1)"
            return reference
        }
    }

    /// Accepts only exact citation tokens returned for this request AND passages
    /// that still exist unchanged in this index. Model-invented IDs never resolve.
    func validatedReferences(in response: String, candidates: [SourceReference]) -> [SourceReference] {
        guard let regex = try? NSRegularExpression(pattern: #"(?<![\[\\])\[S[1-9][0-9]*\](?!\])"#) else { return [] }
        let string = response as NSString
        let matches = regex.matches(in: response, range: NSRange(location: 0, length: string.length))
        let grouped = Dictionary(grouping: candidates, by: \.id)
        var seen: Set<String> = []
        var valid: [SourceReference] = []
        for match in matches {
            let token = string.substring(with: match.range)
            let id = String(token.dropFirst().dropLast())
            guard seen.insert(id).inserted, let matching = grouped[id], matching.count == 1,
                  let current = currentReference(matching[0]) else { continue }
            valid.append(current)
        }
        return valid
    }

    func resolves(_ reference: SourceReference) -> Bool { currentReference(reference) != nil }

    /// Refreshes display names while retaining the request-specific token.
    func currentReference(_ reference: SourceReference) -> SourceReference? {
        let current: SourceReference?
        if let identity = reference.passageID {
            current = byIdentity[identity]
        } else {
            // Backward-compatible saved references must still match exact content.
            current = passages.first { Self.samePassage($0.reference, reference) }?.reference
        }
        guard var current, Self.samePassage(current, reference) else { return nil }
        current.id = reference.id
        return current
    }

    private static func samePassage(_ lhs: SourceReference, _ rhs: SourceReference) -> Bool {
        lhs.materialID == rhs.materialID && lhs.noteID == rhs.noteID
            && lhs.assignmentID == rhs.assignmentID && lhs.page == rhs.page && lhs.excerpt == rhs.excerpt
    }

    private static let stopWords: Set<String> = ["the", "and", "for", "that", "this", "with", "from", "what", "which", "are", "was", "were", "how", "can", "could", "would", "please", "explain", "summarize", "summary", "help", "about", "these", "give", "does", "into", "have", "has", "your", "you", "my"]

    private static func terms(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 || $0.first?.isNumber == true }
    }

    private static func chunks(_ text: String) -> [String] {
        // Bound passages without slicing UTF-8 or splitting a Unicode character.
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        var result: [String] = []
        var start = 0
        while start < words.count {
            var end = start
            var count = 0
            while end < words.count {
                let nextCount = count + words[end].count + (end == start ? 0 : 1)
                if nextCount > 1200 && end > start { break }
                count = nextCount
                end += 1
            }
            let excerpt = words[start..<end].joined(separator: " ")
            // A very long token (e.g. base64 inside a note) must not bypass bounds.
            if excerpt.count > 1600 {
                var cursor = excerpt.startIndex
                while cursor < excerpt.endIndex {
                    let next = excerpt.index(cursor, offsetBy: 1200, limitedBy: excerpt.endIndex) ?? excerpt.endIndex
                    result.append(String(excerpt[cursor..<next]))
                    cursor = next
                }
            } else { result.append(excerpt) }
            if end == words.count { break }
            start = max(start + 1, end - min(24, (end - start) / 4))
        }
        return result
    }
}
