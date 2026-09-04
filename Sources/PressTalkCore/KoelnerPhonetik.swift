import Foundation

/// Kölner Phonetik — the German-language analogue of Soundex.
///
/// Chosen over Soundex/Metaphone because those encode ENGLISH orthography. German
/// needs sch/ch/tz/umlaut handling or the corruptions we actually see do not
/// collide with their targets: "Sofortüberweisung" vs "Sfort Überweisung" is a
/// match under Kölner and a miss under Soundex.
public enum KoelnerPhonetik {
    private static func normalise(_ word: String) -> String {
        var s = word.lowercased()
        for (from, to) in [("ä","a"), ("ö","o"), ("ü","u"), ("ß","ss"),
                           ("é","e"), ("è","e"), ("ç","c"), ("ı","i")] {
            s = s.replacingOccurrences(of: from, with: to)
        }
        return String(s.unicodeScalars.filter { $0 >= "a" && $0 <= "z" }.map(Character.init))
    }

    public static func code(_ word: String) -> String {
        let w = Array(normalise(word))
        guard !w.isEmpty else { return "" }
        var codes = ""
        for (i, ch) in w.enumerated() {
            let prev = i > 0 ? w[i - 1] : Character(" ")
            let next = i + 1 < w.count ? w[i + 1] : Character(" ")
            switch ch {
            case "a", "e", "i", "j", "o", "u", "y": codes += "0"
            case "h": break
            case "b": codes += "1"
            case "p": codes += (next == "h") ? "3" : "1"
            case "d", "t": codes += "csz".contains(next) ? "8" : "2"
            case "f", "v", "w": codes += "3"
            case "g", "k", "q": codes += "4"
            case "c":
                if i == 0 { codes += "ahkloqrux".contains(next) ? "4" : "8" }
                else if "sz".contains(prev) { codes += "8" }
                else { codes += "ahkoqux".contains(next) ? "4" : "8" }
            case "x": codes += "ckq".contains(prev) ? "8" : "48"
            case "l": codes += "5"
            case "m", "n": codes += "6"
            case "r": codes += "7"
            case "s", "z": codes += "8"
            default: break
            }
        }
        // Collapse runs, then drop zeros except a leading one.
        var collapsed = ""
        for c in codes where collapsed.last != c { collapsed.append(c) }
        guard let first = collapsed.first else { return "" }
        return String(first) + collapsed.dropFirst().filter { $0 != "0" }
    }

    public static func code(phrase tokens: [String]) -> String {
        tokens.map(code).joined()
    }

    /// Levenshtein distance, used on both phonetic codes and surface forms.
    public static func editDistance(_ a: String, _ b: String) -> Int {
        if a == b { return 0 }
        let x = Array(a), y = Array(b)
        if x.isEmpty || y.isEmpty { return max(x.count, y.count) }
        var prev = Array(0...y.count)
        for i in 1...x.count {
            var cur = [i]
            for j in 1...y.count {
                cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1)))
            }
            prev = cur
        }
        return prev[y.count]
    }
}
