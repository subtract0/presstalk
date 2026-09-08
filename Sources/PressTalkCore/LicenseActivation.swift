import Foundation

public enum LicenseActivation {
    /// Decode only the explicit activation URL or a bounded local licence file.
    /// This is transport parsing; the signature must still pass before storage.
    public static func encodedLicense(from url: URL) throws -> String {
        if url.isFileURL {
            guard url.pathExtension.lowercased() == "presstalk-license",
                  try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
            else { throw PressTalkLicenseError.malformed("not a licence file") }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: PressTalkLicenseVerifier.maximumEncodedLength + 1) ?? Data()
            guard data.count <= PressTalkLicenseVerifier.maximumEncodedLength,
                  let encoded = String(data: data, encoding: .utf8)
            else { throw PressTalkLicenseError.malformed("unreadable licence file") }
            return encoded
        }
        guard url.absoluteString.utf8.count <= PressTalkLicenseVerifier.maximumEncodedLength + 256,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "presstalk", parts.host?.lowercased() == "activate",
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.path.isEmpty, parts.fragment == nil,
              let items = parts.queryItems, items.count == 1,
              items[0].name == "license", let encoded = items[0].value,
              !encoded.isEmpty
        else { throw PressTalkLicenseError.malformed("invalid activation link") }
        return encoded
    }
}
