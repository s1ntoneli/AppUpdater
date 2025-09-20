import Foundation

public extension Release {
    /// Extract a localized changelog from the GitHub release body.
    ///
    /// Supported format inside the release body (Markdown):
    ///
    /// <!-- au:lang=zh-Hans -->
    /// ...中文更新日志...
    /// <!-- au:end -->
    ///
    /// <!-- au:lang=en -->
    /// ...English changelog...
    /// <!-- au:end -->
    ///
    /// Optional default block:
    /// <!-- au:default --> ... <!-- au:end -->
    ///
    /// If no blocks are found, the original `body` is returned.
    func localizedBody(preferredLanguages: [String]? = nil) -> String {
        let langs = preferredLanguages ?? Locale.preferredLanguages

        // Parse language sections
        let sections = Self.parseLanguageSections(from: body)
        if sections.isEmpty { return body }

        // Try to match preferred languages
        for raw in langs {
            let candidates = Self.languageCandidates(for: raw)
            for cand in candidates {
                if let matched = sections[cand] { return matched }
            }
        }

        // Fallback to `default` block
        if let def = sections["default"] { return def }

        // Fallback to English if provided
        if let en = sections["en"] { return en }

        // Last resort: return the first provided section
        return sections.values.first ?? body
    }

    private static func parseLanguageSections(from text: String) -> [String: String] {
        var result: [String: String] = [:]

        // Pattern for <!-- au:lang=xx -->...<!-- au:end -->
        let langPattern = "<!--\\s*au:lang\\s*=\\s*([A-Za-z0-9_-]+)\\s*-->([\\s\\S]*?)<!--\\s*au:end\\s*-->"
        // Pattern for <!-- au:default -->...<!-- au:end -->
        let defaultPattern = "<!--\\s*au:default\\s*-->([\\s\\S]*?)<!--\\s*au:end\\s*-->"

        func apply(pattern: String, captureKeyAt: Int?) {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) {
                let ns = text as NSString
                let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
                for m in matches {
                    let key: String
                    let contentRange: NSRange
                    if let idx = captureKeyAt {
                        let k = ns.substring(with: m.range(at: idx))
                        key = normalizeLanguageKey(k)
                        contentRange = m.range(at: idx + 1)
                    } else {
                        key = "default"
                        contentRange = m.range(at: 1)
                    }
                    let content = ns.substring(with: contentRange).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !content.isEmpty {
                        result[key] = content
                    }
                }
            }
        }

        apply(pattern: langPattern, captureKeyAt: 1)
        apply(pattern: defaultPattern, captureKeyAt: nil)

        return result
    }

    private static func normalizeLanguageKey(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: "-").lowercased()
    }

    private static func languageCandidates(for raw: String) -> [String] {
        let normalized = normalizeLanguageKey(raw)
        // Split into components and produce progressively shorter candidates
        var parts = normalized.split(separator: "-").map(String.init)
        // Special-case common Simplified/Traditional Chinese tags to improve matching likelihood
        // e.g., zh-cn -> zh-hans, zh-tw -> zh-hant
        if parts.first == "zh" {
            if parts.contains("cn") || parts.contains("hans") { parts = ["zh", "hans"] }
            if parts.contains("tw") || parts.contains("hk") || parts.contains("hant") { parts = ["zh", "hant"] }
        }

        var candidates: [String] = []
        for i in stride(from: parts.count, through: 1, by: -1) {
            candidates.append(parts[0..<i].joined(separator: "-"))
        }
        // Also try plain language if it's not already included (e.g. "en")
        if let base = parts.first, !candidates.contains(base) {
            candidates.append(base)
        }
        return candidates
    }
}
