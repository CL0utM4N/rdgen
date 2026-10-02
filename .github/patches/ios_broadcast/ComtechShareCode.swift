// Comtech: the one-time code a technician uses to see this screen. The app
// makes it and shows it; the broadcast extension, which does the sharing,
// reads it. They can't read each other's files, so it's kept in the
// keychain under an access group both are signed for (TEAMID.comtech.share,
// covered by the TEAMID.* keychain group every development and sideload
// profile carries). Compiled into both the app and the extension.
import Foundation
import Security

enum ComtechShareCode {
    private static let service = "comtech-share"
    private static let account = "one-time-code"

    /// The keychain group shared by the app and its extension, from the
    /// team ID this app was signed with; nil when the keychain won't say
    static func group() -> String? {
        let probe = "comtech-share-probe"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: probe,
            kSecAttrAccount as String: probe,
            kSecReturnAttributes as String: true,
        ]
        var result: CFTypeRef?
        var status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            var add = query
            add.removeValue(forKey: kSecReturnAttributes as String)
            add[kSecValueData as String] = Data()
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
            status = SecItemCopyMatching(query as CFDictionary, &result)
        }
        // the default group is TEAMID.<bundle id>
        guard status == errSecSuccess, let attrs = result as? [String: Any],
              let defaultGroup = attrs[kSecAttrAccessGroup as String] as? String,
              let team = defaultGroup.split(separator: ".").first else { return nil }
        return "\(team).comtech.share"
    }

    private static func base(_ group: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: group,
        ]
    }

    /// The current code, or nil when there isn't one or it can't be shared
    static func read() -> String? {
        guard let group = group() else { return nil }
        var query = base(group)
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let code = String(data: data, encoding: .utf8), !code.isEmpty else { return nil }
        return code
    }

    /// Makes a new code and keeps it where the extension can read it; nil
    /// when the keychain can't share it
    static func renew() -> String? {
        guard let group = group() else { return nil }
        var digits = [UInt8](repeating: 0, count: 6)
        guard SecRandomCopyBytes(kSecRandomDefault, digits.count, &digits) == errSecSuccess else { return nil }
        let code = digits.map { String($0 % 10) }.joined()
        SecItemDelete(base(group) as CFDictionary)
        var add = base(group)
        add[kSecValueData as String] = Data(code.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { return nil }
        return read() == code ? code : nil
    }
}
