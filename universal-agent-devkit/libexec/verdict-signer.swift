// verdict-signer (#632 B): reads a payload on stdin and prints its base64 Ed25519 signature on stdout.
// It runs only as uid _devkitseal (called by verdict-seal-audit). The private key is a 32-byte raw Ed25519 key, base64 in
// the generic-password item service "devkit-verdict-seal" account "ed25519" of _devkitseal's keychain
// ~/Library/Keychains/seal.keychain-db (mode 600, ACL -T this binary). It is read with SecItemCopyMatching in THIS process
// and the signing is done with CryptoKit in this same process. No /usr/bin/security, no exec after the key is read.
// Build: swiftc -O -o verdict-signer verdict-signer.swift (docs/verdict-seal-setup.md).
import CryptoKit
import Foundation
import Security

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(("verdict-signer: " + msg + "\n").data(using: .utf8)!)
    exit(1)
}

let keychainPath = NSHomeDirectory() + "/Library/Keychains/seal.keychain-db"
var keychain: SecKeychain?
if SecKeychainOpen(keychainPath, &keychain) != errSecSuccess || keychain == nil {
    fail("cannot open \(keychainPath)")
}
// The keychain has an empty password: the boundary is the uid (file mode 600), not the password. Unlock after a reboot.
_ = SecKeychainUnlock(keychain, 0, "", true)

let args = CommandLine.arguments.dropFirst()
if args.first == "--generate" {
    // One-time setup (owner, as _devkitseal): create the key in the keychain (ACL: this binary only), print the public key.
    let fresh = Curve25519.Signing.PrivateKey()
    var access: SecAccess?
    var me: SecTrustedApplication?
    guard SecTrustedApplicationCreateFromPath(nil, &me) == errSecSuccess, let app = me,
          SecAccessCreate("devkit-verdict-seal" as CFString, [app] as CFArray, &access) == errSecSuccess else {
        fail("cannot build the keychain ACL")
    }
    let add: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "devkit-verdict-seal",
        kSecAttrAccount as String: "ed25519",
        kSecUseKeychain as String: keychain!,
        kSecAttrAccess as String: access!,
        kSecValueData as String: fresh.rawRepresentation.base64EncodedString().data(using: .utf8)!,
    ]
    let st = SecItemAdd(add as CFDictionary, nil)
    if st != errSecSuccess { fail("SecItemAdd failed (OSStatus \(st)); delete the old item first") }
    print(fresh.publicKey.rawRepresentation.base64EncodedString())
    exit(0)
}

let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "devkit-verdict-seal",
    kSecAttrAccount as String: "ed25519",
    kSecMatchSearchList as String: [keychain!],
    kSecReturnData as String: true,
    kSecMatchLimit as String: kSecMatchLimitOne,
]
var item: CFTypeRef?
let status = SecItemCopyMatching(query as CFDictionary, &item)
guard status == errSecSuccess, let data = item as? Data,
      let b64 = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
      let raw = Data(base64Encoded: b64), raw.count == 32 else {
    fail("key item missing or malformed (OSStatus \(status))")
}
let key: Curve25519.Signing.PrivateKey
do { key = try Curve25519.Signing.PrivateKey(rawRepresentation: raw) } catch { fail("bad key: \(error)") }

if args.first == "--pubkey" {
    print(key.publicKey.rawRepresentation.base64EncodedString())
    exit(0)
}

let payload = FileHandle.standardInput.readDataToEndOfFile()
if payload.isEmpty || payload.count > 1_000_000 { fail("payload empty or too large") }
do {
    let sig = try key.signature(for: payload)
    print(sig.base64EncodedString())
} catch {
    fail("sign failed: \(error)")
}
