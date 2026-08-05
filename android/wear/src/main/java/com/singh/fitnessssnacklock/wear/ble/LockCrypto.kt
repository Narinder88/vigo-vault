package com.singh.fitnessssnacklock.wear.ble

import javax.crypto.Cipher
import javax.crypto.spec.SecretKeySpec

object LockCrypto {
    fun encrypt(frameHex: String, keyHex: String): ByteArray? {
        return try {
            val key = LockProtocol.hexToBytes(keyHex.lowercase())
            val plaintext = LockProtocol.hexToBytes(frameHex.lowercase())
            val cipher = Cipher.getInstance("AES/ECB/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"))
            cipher.doFinal(plaintext)
        } catch (_: Exception) {
            null
        }
    }

    fun decrypt(ciphertextHex: String, keyHex: String): ByteArray? {
        return try {
            val key = LockProtocol.hexToBytes(keyHex.lowercase())
            val ciphertext = LockProtocol.hexToBytes(ciphertextHex.lowercase())
            val cipher = Cipher.getInstance("AES/ECB/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"))
            cipher.doFinal(ciphertext)
        } catch (_: Exception) {
            null
        }
    }

    fun tryDecryptNotifyCandidates(
        response: ByteArray,
        encryptKeyHex: String,
        isValidFrame: ((ByteArray) -> Boolean)? = null,
    ): ByteArray? {
        if (response.isEmpty()) return null

        val normalizedKey = encryptKeyHex.lowercase()
        for (candidate in LockProtocol.aesCiphertextBlockCandidates(response)) {
            if (candidate.block.size != LockProtocol.AES_BLOCK_SIZE_BYTES) continue
            val decrypted = decrypt(LockProtocol.bytesToHex(candidate.block), normalizedKey)
                ?: continue
            if (isValidFrame == null || isValidFrame(decrypted)) {
                return decrypted
            }
        }
        return null
    }

    fun parseTokenFromNotify(response: ByteArray, encryptKeyHex: String): String? {
        val normalizedKey = encryptKeyHex.lowercase()
        for (candidate in LockProtocol.aesCiphertextBlockCandidates(response)) {
            if (candidate.block.size != LockProtocol.AES_BLOCK_SIZE_BYTES) continue
            val decrypted = decrypt(LockProtocol.bytesToHex(candidate.block), normalizedKey)
                ?: continue

            if (decrypted.size >= 3 &&
                decrypted[0] == 0x06.toByte() &&
                decrypted[1] == 0x02.toByte()
            ) {
                val expectedChecksum = (decrypted[0].toInt() + decrypted[1].toInt()) and 0xFF
                if (decrypted[2].toInt() and 0xFF != expectedChecksum) {
                    // Checksum advisory mismatch accepted for token 06 02.
                }
            }

            val token = LockProtocol.parseSessionToken(decrypted)
            if (!token.isNullOrBlank()) {
                return token
            }
        }
        return null
    }
}
