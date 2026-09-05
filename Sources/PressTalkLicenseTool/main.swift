import CryptoKit
import Foundation
import PressTalkCore

/// Issues PressTalk licences. Run by the owner, on the owner's machine, against
/// a private key that never ships.
///
/// Deliberately not a service. A licence server is infrastructure someone has to
/// keep alive forever, and a buy-once local app that stops working when that
/// server does has broken its own promise.

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func usage() -> Never {
    print("""
    presstalk-license — issue and check offline PressTalk licences

    generate-key --out <dir> --key-id <id>
        Writes <id>.private.key and <id>.public.key. Back up the private key
        somewhere encrypted; losing it means no further licences can be issued
        for keys already shipped in the app.

    issue --key <path to private key> --key-id <id> --entitlement <personal|founder|commercial>
          [--max-major <n>] [--count <n>]
        --max-major defaults to unbounded. Pass a number only for a deliberately
        bounded entitlement.
        Prints one licence per line.

    verify --public-key <path> --key-id <id> --license <string> [--running-major <n>]
        Checks a licence the way the app does.

    inspect --license <string>
        Decodes the payload WITHOUT verifying it. For support, so a customer's
        key can be read without trusting it.
    """)
    exit(2)
}

func argument(_ name: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: "--\(name)"), index + 1 < arguments.count else {
        return nil
    }
    return arguments[index + 1]
}

func requiredArgument(_ name: String, in arguments: [String]) -> String {
    guard let value = argument(name, in: arguments) else { fail("Missing --\(name)") }
    return value
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { usage() }

switch command {
case "generate-key":
    let directory = requiredArgument("out", in: arguments)
    let keyID = requiredArgument("key-id", in: arguments)
    let privateKey = Curve25519.Signing.PrivateKey()

    let privateURL = URL(fileURLWithPath: directory).appendingPathComponent("\(keyID).private.key")
    let publicURL = URL(fileURLWithPath: directory).appendingPathComponent("\(keyID).public.key")
    guard !FileManager.default.fileExists(atPath: privateURL.path) else {
        fail("Refusing to overwrite \(privateURL.path)")
    }

    try privateKey.rawRepresentation.base64EncodedString()
        .write(to: privateURL, atomically: true, encoding: .utf8)
    // Owner-read-only. A signing key with default permissions is a signing key
    // in everyone's backup.
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: privateURL.path)
    try privateKey.publicKey.rawRepresentation.base64EncodedString()
        .write(to: publicURL, atomically: true, encoding: .utf8)

    print("private key  \(privateURL.path)  (mode 600, back this up encrypted)")
    print("public key   \(publicURL.path)")
    print()
    print("Add to the app's trusted keys as:")
    print("  \"\(keyID)\": \"\(privateKey.publicKey.rawRepresentation.base64EncodedString())\"")

case "issue":
    let keyPath = requiredArgument("key", in: arguments)
    let keyID = requiredArgument("key-id", in: arguments)
    let entitlement = requiredArgument("entitlement", in: arguments)
    guard PressTalkLicense.Entitlement(rawValue: entitlement) != nil else {
        fail("Unknown entitlement: \(entitlement)")
    }
    // Unbounded by default: the offer is every future Mac update, free.
    let maxMajor = Int(argument("max-major", in: arguments)
        ?? String(PressTalkLicense.allMajorVersions)) ?? PressTalkLicense.allMajorVersions
    let count = Int(argument("count", in: arguments) ?? "1") ?? 1

    let raw = try String(contentsOfFile: keyPath, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let keyData = Data(base64Encoded: raw),
          let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: keyData)
    else {
        fail("Could not read a signing key from \(keyPath)")
    }

    let issuer = PressTalkLicenseIssuer(keyID: keyID, privateKey: privateKey)
    for _ in 0..<count {
        let license = PressTalkLicense(
            keyID: keyID,
            productID: PressTalkLicense.productIdentifier,
            licenseID: UUID().uuidString,
            entitlement: entitlement,
            issuedAt: Date(),
            maxMajorVersion: maxMajor)
        print(try issuer.issue(license))
    }

case "verify":
    let publicKeyPath = requiredArgument("public-key", in: arguments)
    let keyID = requiredArgument("key-id", in: arguments)
    let licenseString = requiredArgument("license", in: arguments)
    let runningMajor = Int(argument("running-major", in: arguments) ?? "1") ?? 1

    let raw = try String(contentsOfFile: publicKeyPath, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let keyData = Data(base64Encoded: raw),
          let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData)
    else {
        fail("Could not read a public key from \(publicKeyPath)")
    }

    let verifier = PressTalkLicenseVerifier(
        trustedKeys: [keyID: publicKey], runningMajorVersion: runningMajor)
    switch verifier.verify(licenseString) {
    case .success(let license):
        print("valid")
        print("  entitlement     \(license.entitlement)")
        print("  licence id      \(license.licenseID)")
        print("  issued          \(ISO8601DateFormatter().string(from: license.issuedAt))")
        print("  covers          " + (license.maxMajorVersion == PressTalkLicense.allMajorVersions
            ? "every future version" : "up to \(license.maxMajorVersion).x"))
    case .failure(let error):
        fail("invalid: \(error)  (\(error.userFacingMessage))")
    }

case "inspect":
    let licenseString = requiredArgument("license", in: arguments)
    let parts = licenseString.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".")
    guard parts.count == 4, let payload = Data(base64URLEncoded: String(parts[2])) else {
        fail("Not a readable licence string")
    }
    print("NOT VERIFIED — this only decodes the payload.")
    print(String(data: payload, encoding: .utf8) ?? "<undecodable>")

default:
    usage()
}
