import Foundation
import Security

final class PairedLockSecureStorage {
    private let service = "com.singh.fitnessssnacklock.paired_locks"
    private let account = "paired_lock_ids"

    func getPairedIds() -> Set<String> {
        guard let data = readKeychainData(),
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
    }

    private func savePairedIds(_ ids: Set<String>) {
        guard let data = try? JSONEncoder().encode(Array(ids)) else {
            return
        }

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

    private func readKeychainData() -> Data? {
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
