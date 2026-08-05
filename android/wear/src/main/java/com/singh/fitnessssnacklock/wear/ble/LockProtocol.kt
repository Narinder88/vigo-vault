package com.singh.fitnessssnacklock.wear.ble

object LockProtocol {
    const val FRAME_SIZE_BYTES = 16
    const val AES_BLOCK_SIZE_BYTES = 16
    const val DEFAULT_ENCRYPT_KEY = "3A60432A5C01211F291E0F4E0C132825"
    const val DEFAULT_UNLOCK_SERIAL_HEX = "000001"

    val DEFAULT_PASSWORD_BYTES = byteArrayOf(
        0x30, 0x30, 0x30, 0x30, 0x30, 0x30,
    )

    val LOCK_SERVICE_UUID = java.util.UUID.fromString("0000fee7-0000-1000-8000-00805f9b34fb")
    val LOCK_WRITE_CHARACTERISTIC_UUID =
        java.util.UUID.fromString("000036f5-0000-1000-8000-00805f9b34fb")
    val LOCK_NOTIFY_CHARACTERISTIC_UUID =
        java.util.UUID.fromString("000036f6-0000-1000-8000-00805f9b34fb")

    val FRAMED_NOTIFY_SUFFIX = byteArrayOf(
        0xC1.toByte(), 0xD3.toByte(), 0x86.toByte(), 0x60.toByte(),
        0x97.toByte(), 0xC7.toByte(), 0x75.toByte(), 0x91.toByte(),
    )

    fun tokenRequestFrameHex(): String {
        return frameToHex(byteArrayOf(0x06, 0x01, 0x01, 0x01, 0x00))
    }

    fun unlockFrameHex(tokenHex: String, serialHex: String = DEFAULT_UNLOCK_SERIAL_HEX): String {
        val tokenBytes = decodeFixedBytes(tokenHex, 4, "TOKEN")
        val serialBytes = decodeFixedBytes(serialHex, 3, "SN")
        val frame = ByteArray(16)
        frame[0] = 0x05
        frame[1] = 0x01
        frame[2] = 0x06
        System.arraycopy(DEFAULT_PASSWORD_BYTES, 0, frame, 3, DEFAULT_PASSWORD_BYTES.size)
        System.arraycopy(tokenBytes, 0, frame, 9, tokenBytes.size)
        System.arraycopy(serialBytes, 0, frame, 13, serialBytes.size)
        return bytesToHex(frame)
    }

    fun parseSessionToken(decrypted: ByteArray): String? {
        if (decrypted.size < 7) return null
        if (decrypted[0] != 0x06.toByte() || decrypted[1] != 0x02.toByte()) return null
        return bytesToHex(decrypted.copyOfRange(3, 7))
    }

    fun isPasswordCommandAck(decrypted: ByteArray?): Boolean {
        if (decrypted == null || decrypted.size < 4) return false

        if (decrypted[0] == 0x05.toByte() &&
            decrypted[1] == 0x02.toByte() &&
            decrypted[2] == 0x01.toByte()
        ) {
            return decrypted[3] == 0x00.toByte()
        }

        if (decrypted[0] == 0x05.toByte() &&
            decrypted[1] == 0x01.toByte() &&
            decrypted[2] == 0x06.toByte()
        ) {
            return decrypted[3] != 0x00.toByte() && decrypted[3] != 0xFF.toByte()
        }

        return false
    }

    fun isFramedSuffixNotify(response: ByteArray): Boolean {
        if (response.size != 20) return false
        if (response[16] != 0x00.toByte() ||
            response[17] != 0x00.toByte() ||
            response[18] != 0x00.toByte() ||
            response[19] != 0x00.toByte()
        ) {
            return false
        }
        for (i in FRAMED_NOTIFY_SUFFIX.indices) {
            if (response[8 + i] != FRAMED_NOTIFY_SUFFIX[i]) return false
        }
        return true
    }

    data class AesCandidate(val block: ByteArray, val label: String)

    fun aesCiphertextBlockCandidates(response: ByteArray): List<AesCandidate> {
        if (response.size <= AES_BLOCK_SIZE_BYTES) {
            if (response.size < AES_BLOCK_SIZE_BYTES) {
                return listOf(
                    AesCandidate(padToAesBlock(response), "padded-${response.size}b"),
                )
            }
            return listOf(AesCandidate(response.copyOf(), "full-${response.size}b"))
        }

        if (response.size == 20 && isFramedSuffixNotify(response)) {
            val prefix8 = response.copyOfRange(0, 8)
            val dynamic6 = response.copyOfRange(2, 8)
            val tail4 = response.copyOfRange(16, 20)
            val suffix8 = response.copyOfRange(8, 16)
            return listOf(
                AesCandidate(padToAesBlock(prefix8), "prefix[0:8]-zpad"),
                AesCandidate(padToAesBlock(dynamic6), "dynamic[2:8]-zpad"),
                AesCandidate(padToAesBlock(prefix8 + tail4), "stripSuffix[0:8+16:20]-zpad"),
                AesCandidate(padToAesBlock(dynamic6 + tail4), "stripSuffix[2:8+16:20]-zpad"),
                AesCandidate(padToAesBlock(dynamic6 + suffix8), "dynamic[2:8]+suffix[8:16]"),
                AesCandidate(padToAesBlock(prefix8 + prefix8), "prefix[0:8]x2"),
                AesCandidate(response.copyOfRange(0, 16), "window[0:16]"),
                AesCandidate(response.copyOfRange(2, 18), "window[2:18]"),
                AesCandidate(response.copyOfRange(4, 20), "window[4:20]"),
            )
        }

        if (response.size == 20) {
            return listOf(
                AesCandidate(response.copyOfRange(0, 16), "window[0:16]"),
                AesCandidate(response.copyOfRange(2, 18), "window[2:18]"),
                AesCandidate(response.copyOfRange(4, 20), "window[4:20]"),
            )
        }

        return listOf(AesCandidate(response.copyOfRange(0, 16), "window[0:16]"))
    }

    private fun padToAesBlock(bytes: ByteArray): ByteArray {
        val block = ByteArray(AES_BLOCK_SIZE_BYTES)
        System.arraycopy(bytes, 0, block, 0, minOf(bytes.size, AES_BLOCK_SIZE_BYTES))
        return block
    }

    private fun frameToHex(bytes: ByteArray): String {
        val frame = ByteArray(FRAME_SIZE_BYTES)
        System.arraycopy(bytes, 0, frame, 0, minOf(bytes.size, FRAME_SIZE_BYTES))
        return bytesToHex(frame)
    }

    private fun decodeFixedBytes(hexValue: String, expectedBytes: Int, label: String): ByteArray {
        val normalized = hexValue.lowercase()
        require(normalized.length == expectedBytes * 2) {
            "$label must be ${expectedBytes * 2} hex characters."
        }
        return hexToBytes(normalized)
    }

    fun hexToBytes(hex: String): ByteArray {
        val normalized = hex.replace(":", "").lowercase()
        require(normalized.length % 2 == 0) { "Invalid hex string length" }
        return ByteArray(normalized.length / 2) { index ->
            normalized.substring(index * 2, index * 2 + 2).toInt(16).toByte()
        }
    }

    fun bytesToHex(bytes: ByteArray): String {
        return bytes.joinToString("") { byte ->
            "%02x".format(byte.toInt() and 0xFF)
        }
    }
}
