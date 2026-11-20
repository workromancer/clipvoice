import Foundation

/// Resolves canonical and voice-transcribed clip identifiers (e.g. "clip-4", "clip 4", "4", "clip four").
public enum SpeakableID {
    public static func makeID(sequence: Int) -> String {
        "clip-\(sequence)"
    }

    public static func parseSequence(from input: String) -> Int? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        // Direct integer or "#4"
        if let direct = Int(trimmed), direct > 0 {
            return direct
        }
        if trimmed.hasPrefix("#"), let afterHash = Int(trimmed.dropFirst()), afterHash > 0 {
            return afterHash
        }

        // Normalize separators and common prefixes ("clip-4", "clip 4", "clip_4", "클립 4", "클립4")
        var normalized = trimmed
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")

        for prefix in ["clip ", "clip", "클립 ", "클립"] {
            if normalized.hasPrefix(prefix) {
                let rest = String(normalized.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespaces)
                if let value = parseNumberToken(rest), value > 0 {
                    return value
                }
            }
        }

        if let wordNumber = parseNumberToken(normalized), wordNumber > 0 {
            return wordNumber
        }

        // Fallback: if string starts with "clip" or ends with digits
        normalized = normalized.trimmingCharacters(in: .whitespaces)
        if normalized.hasPrefix("number "), let value = parseNumberToken(String(normalized.dropFirst(7))) {
            return value > 0 ? value : nil
        }

        return nil
    }

    public static func resolve(_ query: String, in items: [ClipItem]) -> ClipItem? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let exact = items.first(where: { $0.id.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return exact
        }

        if let seq = parseSequence(from: trimmed) {
            return items.first(where: { $0.sequence == seq })
        }

        return nil
    }

    private static func parseNumberToken(_ raw: String) -> Int? {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct = Int(clean) {
            return direct
        }

        let units: [String: Int] = [
            "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4,
            "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
            "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
            "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19
        ]
        if let val = units[clean] {
            return val
        }

        let tens: [String: Int] = [
            "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
            "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90
        ]
        if let val = tens[clean] {
            return val
        }

        let parts = clean.split(separator: " ").map(String.init)
        if parts.count == 2, let t = tens[parts[0]], let u = units[parts[1]], u < 10 {
            return t + u
        }

        return nil
    }
}
