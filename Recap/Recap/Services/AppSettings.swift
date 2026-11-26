import Foundation
import Security

/// Which AI does the work.
enum AIEngine: String, CaseIterable, Identifiable {
    case apple
    case claude

    var id: Self { self }

    var name: String {
        switch self {
        case .apple: "Apple Intelligence"
        case .claude: "Claude"
        }
    }

    var detail: String {
        switch self {
        case .apple: "On your phone. Free and private."
        case .claude: "Best quality. Needs an API key (a few cents per use)."
        }
    }
}

enum SettingsKey {
    static let summaryEngine = "summaryEngine"
    static let interviewEngine = "interviewEngine"
    static let reminderEnabled = "reminderEnabled"
    static let reminderHour = "reminderHour"
    static let reminderMinute = "reminderMinute"
}

enum AIConfig {
    static let claudeKeyAccount = "anthropic-api-key"

    /// Daily summaries default to Apple Intelligence: free, private, and good at one-day summaries.
    static var summaryEngine: AIEngine {
        AIEngine(rawValue: UserDefaults.standard.string(forKey: SettingsKey.summaryEngine) ?? "") ?? .apple
    }

    /// Interview prep defaults to Claude, which is much better at reasoning across months of entries.
    static var interviewEngine: AIEngine {
        AIEngine(rawValue: UserDefaults.standard.string(forKey: SettingsKey.interviewEngine) ?? "") ?? .claude
    }

    static var claudeKey: String? {
        guard let key = KeychainStore.string(for: claudeKeyAccount)?.trimmed, !key.isEmpty else { return nil }
        return key
    }
}

/// Stores the Claude API key in the iOS Keychain, never in plain settings.
enum KeychainStore {
    private static let service = Bundle.main.bundleIdentifier ?? "Recap"

    static func string(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String?, for account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.trimmed.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.trimmed.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}
