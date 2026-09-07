import Foundation

/// Finds the package's resource bundle without crashing when it is missing.
///
/// SwiftPM generates an accessor for `Bundle.module` that looks in exactly two
/// places and calls `fatalError` if neither exists:
///
///   1. `Bundle.main.bundleURL/JarvisTap_PressTalkCore.bundle`
///   2. an absolute path into the machine that built it, e.g.
///      `/Users/am/Code/presstalk/.build/.../JarvisTap_PressTalkCore.bundle`
///
/// Packaging puts the bundle at `PressTalk.app/Contents/Resources/`, which is
/// neither. So on any Mac that is not the original build checkout, the first
/// call to `Bundle.module` killed the process. The first dictation reaches it
/// through the vocabulary guard list, so a customer's first use terminated the
/// app with no message. To them the app simply disappeared.
///
/// It survived every check because every Mac that had run PressTalk either was
/// the build machine or had been rebuilt from source on it, so the absolute
/// fallback resolved. A fresh account cannot read another user's home
/// directory, which is exactly the case nobody had.
///
/// This resolver never touches `Bundle.module` -- reading it at all runs the
/// generated closure and can abort the process -- and returns nil rather than
/// crashing. A missing vocabulary list costs some German repair quality. It
/// must never cost the user their dictation.
public enum PressTalkResources {
    /// Only exists so `Bundle(for:)` can report where this code was loaded
    /// from. That is the one anchor that works in every layout -- inside a
    /// .app, beside a bare executable, and next to an .xctest bundle -- because
    /// it asks the runtime rather than guessing from the main bundle.
    private final class Marker {}

    public static let bundleName = "JarvisTap_PressTalkCore.bundle"

    public static let bundle: Bundle? = {
        var candidates: [URL] = []

        // Where packaging actually puts it inside a .app.
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent(bundleName))
        }
        // Where SwiftPM's own accessor expects it, for a bare executable.
        candidates.append(Bundle.main.bundleURL.appendingPathComponent(bundleName))
        // Beside the executable, which is how a command-line tool is laid out.
        candidates.append(
            Bundle.main.bundleURL
                .deletingLastPathComponent()
                .appendingPathComponent(bundleName))
        // A bundle that already carries the resources directly.
        candidates.append(Bundle.main.bundleURL)

        // Anchored on where this code actually loaded from, which is the only
        // candidate that holds under `swift test`: there Bundle.main is the
        // xctest runner, sitting somewhere unrelated to the built products.
        let own = Bundle(for: Marker.self).bundleURL
        candidates.append(own.appendingPathComponent(bundleName))
        candidates.append(own.deletingLastPathComponent().appendingPathComponent(bundleName))
        candidates.append(own)

        for url in candidates {
            if let bundle = Bundle(url: url),
               bundle.url(forResource: "de_user_vocabulary", withExtension: "txt") != nil {
                return bundle
            }
        }
        return nil
    }()
}
