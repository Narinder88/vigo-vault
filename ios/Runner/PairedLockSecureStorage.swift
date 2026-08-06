import Foundation
import Security

final class PairedLockSecureStorage {
    private let pairedService = "com.singh.fitnessssnacklock.paired_locks"
    private let pairedAccount = "paired_lock_ids"
    private let secretsService = "com.singh.fitnessssnacklock.lock_secrets"
    private let secretsAccount = "lock_secret_keys"

    func getPairedIds() -> Set<String> {
        guard let data = readKeychainData(service: pairedService, account: pairedAccount),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(ids)
    }

    func isPaired(deviceId: String) -> Bool {
        return getPairedIds().contains(deviceId)
    }

    func pair(deviceId: String) {
        var ids = getPairedIds()
        ids.insert(deviceId)
        savePairedIds(ids)
    }

    func unpair(deviceId: String) {
        var ids = getPairedIds()
        ids.remove(deviceId)
        savePairedIds(ids)
        removeSecretKey(deviceId: deviceId)
    }

    func getSecretKey(deviceId: String) -> String? {
        guard let raw = getSecretKeys()[deviceId] else {
            return nil
        }
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ":", with: "")
            .lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    func saveSecretKey(deviceId: String, secretKey: String) {
        var secrets = getSecretKeys()
        secrets[deviceId] = secretKey
        saveSecretKeys(secrets)
    }

    func removeSecretKey(deviceId: String) {
        var secrets = getSecretKeys()
        secrets.removeValue(forKey: deviceId)
        saveSecretKeys(secrets)
    }

    func hasSecretKey(deviceId: String) -> Bool {
        guard let secretKey = getSecretKey(deviceId: deviceId) else {
            return false
        }
        return !secretKey.isEmpty
    }

    private func savePairedIds(_ ids: Set<String>) {
        guard let data = try? JSONEncoder().encode(Array(ids)) else {
            return
        }
        writeKeychainData(
            data,
            service: pairedService,
            account: pairedAccount
        )
    }

    private func getSecretKeys() -> [String: String] {
        guard let data = readKeychainData(service: secretsService, account: secretsAccount),
              let secrets = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return secrets
    }

    private func saveSecretKeys(_ secrets: [String: String]) {
        guard let data = try? JSONEncoder().encode(secrets) else {
            return
        }
        writeKeychainData(
            data,
            service: secretsService,
            account: secretsAccount
        )
    }

    private func writeKeychainData(_ data: Data, service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        } else {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    private func readKeychainData(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            return nil
        }
        return result as? Data
    }
}
