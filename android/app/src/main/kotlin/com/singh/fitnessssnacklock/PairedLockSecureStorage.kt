package com.singh.fitnessssnacklock

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKeys
import org.json.JSONObject

class PairedLockSecureStorage(context: Context) {
    private val prefs = EncryptedSharedPreferences.create(
        PREFS_FILE_NAME,
        MasterKeys.getOrCreate(MasterKeys.AES256_GCM_SPEC),
        context,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )

    fun getPairedIds(): Set<String> {
        return prefs.getStringSet(PAIRED_IDS_KEY, emptySet())?.toSet() ?: emptySet()
    }

    fun isPaired(deviceId: String): Boolean {
        return getPairedIds().contains(deviceId)
    }

    fun pair(deviceId: String) {
        val updated = getPairedIds().toMutableSet()
        updated.add(deviceId)
        prefs.edit().putStringSet(PAIRED_IDS_KEY, updated).apply()
    }

    fun unpair(deviceId: String) {
        val updated = getPairedIds().toMutableSet()
        updated.remove(deviceId)
        prefs.edit().putStringSet(PAIRED_IDS_KEY, updated).apply()
        removeSecretKey(deviceId)
        removePassword(deviceId)
    }

    fun getSecretKey(deviceId: String): String? {
        return getSecretKeys()[deviceId]
    }

    fun saveSecretKey(deviceId: String, secretKey: String) {
        val secrets = getSecretKeys().toMutableMap()
        secrets[deviceId] = secretKey
        persistSecretKeys(secrets)
    }

    fun removeSecretKey(deviceId: String) {
        val secrets = getSecretKeys().toMutableMap()
        secrets.remove(deviceId)
        persistSecretKeys(secrets)
    }

    fun hasSecretKey(deviceId: String): Boolean {
        return getSecretKey(deviceId)?.isNotEmpty() == true
    }

    fun getPassword(deviceId: String): String? {
        return getPasswords()[deviceId]
    }

    fun savePassword(deviceId: String, password: String) {
        val passwords = getPasswords().toMutableMap()
        passwords[deviceId] = password
        persistPasswords(passwords)
    }

    fun removePassword(deviceId: String) {
        val passwords = getPasswords().toMutableMap()
        passwords.remove(deviceId)
        persistPasswords(passwords)
    }

    fun hasPassword(deviceId: String): Boolean {
        return getPassword(deviceId)?.isNotEmpty() == true
    }

    private fun getSecretKeys(): Map<String, String> {
        val raw = prefs.getString(SECRETS_KEY, null) ?: return emptyMap()
        val json = JSONObject(raw)
        val secrets = mutableMapOf<String, String>()
        for (key in json.keys()) {
            secrets[key] = json.getString(key)
        }
        return secrets
    }

    private fun persistSecretKeys(secrets: Map<String, String>) {
        val json = JSONObject()
        for ((deviceId, secretKey) in secrets) {
            json.put(deviceId, secretKey)
        }
        prefs.edit().putString(SECRETS_KEY, json.toString()).apply()
    }

    private fun getPasswords(): Map<String, String> {
        val raw = prefs.getString(PASSWORDS_KEY, null) ?: return emptyMap()
        val json = JSONObject(raw)
        val passwords = mutableMapOf<String, String>()
        for (key in json.keys()) {
            passwords[key] = json.getString(key)
        }
        return passwords
    }

    private fun persistPasswords(passwords: Map<String, String>) {
        val json = JSONObject()
        for ((deviceId, password) in passwords) {
            json.put(deviceId, password)
        }
        prefs.edit().putString(PASSWORDS_KEY, json.toString()).apply()
    }

    companion object {
        private const val PREFS_FILE_NAME = "vigo_vault_paired_locks"
        private const val PAIRED_IDS_KEY = "paired_lock_ids"
        private const val SECRETS_KEY = "lock_secret_keys"
        private const val PASSWORDS_KEY = "lock_passwords"
    }
}
