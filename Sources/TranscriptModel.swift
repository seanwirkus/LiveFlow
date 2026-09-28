import Foundation
import NaturalLanguage
import SwiftUI

/// `id` is derived from the word's position in the stream plus its text, not a
/// random UUID: partial results re-tokenize constantly, and a stable id keeps
/// already-spoken words from re-animating on every recognizer update. When a
/// partial revises a word, the id changes and that word alone cross-fades.
struct Token: Identifiable {
    let index: Int
    var text: String
    let kind: TokenKind

    var id: String { "\(index)|\(text)" }
}

enum TokenKind {
    case noun, verb, adjective, adverb, connector, other

    var color: Color {
        switch self {
        case .noun:      return Color(red: 0.49, green: 0.83, blue: 0.99)  // sky blue
        case .verb:      return Color(red: 0.53, green: 0.94, blue: 0.67)  // mint green
        case .adjective: return Color(red: 0.99, green: 0.83, blue: 0.30)  // amber
        case .adverb:    return Color(red: 0.98, green: 0.66, blue: 0.83)  // pink
        case .connector: return Color(white: 0.62)                          // dim gray
        case .other:     return Color(white: 0.92)                          // near white
        }
    }
}

enum TextSize: String, CaseIterable {
    case small, medium, large

    var title: String { rawValue.capitalized }

    var fontSize: CGFloat {
        switch self {
        case .small:  return 17
        case .medium: return 23
        case .large:  return 30
        }
    }

    var wordSpacing: CGFloat {
        switch self {
        case .small:  return 7
        case .medium: return 9
        case .large:  return 12
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .small:  return 18
        case .medium: return 22
        case .large:  return 28
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .small:  return 10
        case .medium: return 12
        case .large:  return 15
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .small:  return 14
        case .medium: return 17
        case .large:  return 21
        }
    }
}

final class TranscriptModel: ObservableObject {
    @Published var committedTokens: [Token] = []
    @Published var volatileTokens: [Token] = []
    @Published var isListening = false

    @Published var textSize: TextSize = {
        let raw = UserDefaults.standard.string(forKey: "textSize") ?? TextSize.medium.rawValue
        return TextSize(rawValue: raw) ?? .medium
    }() {
        didSet { UserDefaults.standard.set(textSize.rawValue, forKey: "textSize") }
    }

    var volatileText: String = "" {
        didSet {
            volatileTokens = volatileText.isEmpty
                ? []
                : POSTagger.tokenize(volatileText, startIndex: committedTokens.count)
        }
    }

    /// The trailing words currently on screen: committed words plus whatever the
    /// recognizer is still hearing, capped to the most recent few.
    func recentTokens(limit: Int) -> [Token] {
        Array((committedTokens + volatileTokens).suffix(limit))
    }

    private var sentences: [String] = []

    var fullTranscript: String {
        sentences.joined(separator: " ")
    }

    func reset() {
        committedTokens = []
        volatileText = ""
        volatileTokens = []
        sentences = []
    }

    /// Replace rough live segments with the current-generation model's final
    /// pass over the complete utterance.
    func replaceTranscript(with raw: String) {
        reset()
        commitRaw(raw)
    }

    /// A pause mid-sentence produces a new recognizer segment, but it is not a
    /// new sentence — only capitalize when the previous segment actually ended one.
    private var continuingSentence: Bool {
        guard let last = sentences.last?.trimmingCharacters(in: .whitespaces),
              let final = last.last else { return false }
        return !".!?".contains(final)
    }

    func commitRaw(_ raw: String) {
        let cleaned = Cleaner.clean(raw, continuing: continuingSentence)
        guard !cleaned.isEmpty else { return }
        sentences.append(cleaned)
        committedTokens.append(contentsOf: POSTagger.tokenize(cleaned, startIndex: committedTokens.count))
    }
}

enum POSTagger {
    static func tokenize(_ text: String, startIndex: Int = 0) -> [Token] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        var out: [Token] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex,
                             unit: .word,
                             scheme: .lexicalClass,
                             options: [.omitWhitespace]) { tag, range in
            let word = String(text[range])
            let isPunct = tag == .punctuation || tag == .sentenceTerminator
                || word.range(of: #"^[.,!?;:'"()\-]+$"#, options: .regularExpression) != nil
            if isPunct, !out.isEmpty {
                out[out.count - 1].text += word
            } else {
                out.append(Token(index: startIndex + out.count, text: word, kind: kind(for: tag)))
            }
            return true
        }
        return out
    }

    private static func kind(for tag: NLTag?) -> TokenKind {
        switch tag {
        case .noun:                                             return .noun
        case .verb:                                             return .verb
        case .adjective:                                        return .adjective
        case .adverb:                                           return .adverb
        case .conjunction, .preposition, .determiner,
             .pronoun, .particle:                               return .connector
        default:                                                return .other
        }
    }
}

enum Cleaner {
    /// - Parameter continuing: true when this segment continues an unfinished
    ///   sentence, in which case its first word must NOT be capitalized.
    static func clean(_ raw: String, continuing: Bool) -> String {
        var s = Vocabulary.normalize(raw)
        let fillers = [#"\bu+m+\b"#, #"\bu+h+\b"#, #"\berm+\b"#, #"\bmm+hm+\b"#, #"\bhm+\b"#]
        for f in fillers {
            s = s.replacingOccurrences(of: f + #"[,.]?\s?"#, with: "",
                                       options: [.regularExpression, .caseInsensitive])
        }
        s = s.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return fixCapitalization(s, continuing: continuing)
    }

    /// The recognizer capitalizes opportunistically after pauses, which yields
    /// text like "the Shows Above Every thing". Capitalize only at real sentence
    /// starts, and strip stray mid-sentence capitals unless the word is a proper
    /// name, an acronym, or "I".
    static func fixCapitalization(_ text: String, continuing: Bool) -> String {
        guard !text.isEmpty else { return text }

        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var edits: [(Range<String.Index>, String)] = []
        var atSentenceStart = !continuing

        tagger.enumerateTags(in: text.startIndex..<text.endIndex,
                             unit: .word,
                             scheme: .nameType,
                             options: [.omitWhitespace]) { tag, range in
            let word = String(text[range])
            guard let first = word.first else { return true }

            // NLTagger keeps trailing punctuation attached to the word, so a
            // token arrives as "sentence." rather than "sentence" plus ".".
            let core = word.trimmingCharacters(in: .punctuationCharacters)
            let isName = tag == .personalName || tag == .placeName || tag == .organizationName
            let isAcronym = core.count > 1 && core == core.uppercased()
            let preserveCapitalization = Vocabulary.preservesCapitalization(of: core)
                || (core.caseInsensitiveCompare("c") == .orderedSame
                    && text[..<range.lowerBound].hasSuffix("USB-"))
            let closing = CharacterSet(charactersIn: "\"')]}\u{201D}\u{2019}")
            let endsSentence = !isAcronym
                && (word.trimmingCharacters(in: closing).last.map { ".!?".contains($0) } ?? false)

            defer { if endsSentence { atSentenceStart = true } }

            guard !core.isEmpty else { return true }

            // The pronoun "I" is always capitalized, wherever it lands.
            if core == "i" || core.hasPrefix("i'") {
                edits.append((range, "I" + word.dropFirst()))
                atSentenceStart = false
                return true
            }

            if atSentenceStart {
                if first.isLowercase {
                    edits.append((range, first.uppercased() + word.dropFirst()))
                }
                atSentenceStart = false
            } else if first.isUppercase, !isName, !isAcronym, !preserveCapitalization,
                      core != "I", !core.hasPrefix("I'") {
                edits.append((range, first.lowercased() + word.dropFirst()))
            }
            return true
        }

        var out = ""
        var cursor = text.startIndex
        for (range, replacement) in edits {
            out += text[cursor..<range.lowerBound]
            out += replacement
            cursor = range.upperBound
        }
        out += text[cursor...]
        return out
    }
}
