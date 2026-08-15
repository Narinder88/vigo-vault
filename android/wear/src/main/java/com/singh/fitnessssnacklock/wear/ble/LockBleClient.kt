package com.singh.fitnessssnacklock.wear.ble

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.os.Build
import android.util.Log
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeout
import java.util.UUID

class LockBleClient(
    private val context: Context,
) {
    sealed class UnlockResult {
        data object Success : UnlockResult()
        data class Failure(val message: String) : UnlockResult()
    }

    @SuppressLint("MissingPermission")
    suspend fun connectAndUnlock(
        macAddress: String,
        secretKey: String,
        passwordHex: String = LockProtocol.DEFAULT_PASSWORD_HEX,
    ): UnlockResult {
        val adapter = BluetoothAdapter.getDefaultAdapter()
            ?: return UnlockResult.Failure("Bluetooth unavailable")

        if (!adapter.isEnabled) {
            return UnlockResult.Failure("Bluetooth is disabled")
        }

        val normalizedMac = normalizeMacAddress(macAddress)
        val encryptKey = secretKey.ifBlank { LockProtocol.DEFAULT_ENCRYPT_KEY }.lowercase()
        val session = GattSession(context)
        var notifyCharacteristic: BluetoothGattCharacteristic? = null

        return try {
            Log.d(TAG, "Connecting to lock $normalizedMac")
            val device = adapter.getRemoteDevice(normalizedMac)
            session.connect(device)

            val services = session.discoverServices()
            val writeCharacteristic = findWriteCharacteristic(services)
                ?: return UnlockResult.Failure("Lock write characteristic not found")
            notifyCharacteristic = findNotifyCharacteristic(services)
                ?: return UnlockResult.Failure("Lock notify characteristic not found")

            session.enableNotifications(notifyCharacteristic)
            session.flushNotifyBuffer(notifyCharacteristic)
            delay(200)

            val token = performHandshake(
                session,
                writeCharacteristic,
                notifyCharacteristic,
                encryptKey,
            ) ?: return UnlockResult.Failure(HANDSHAKE_FAILED_MESSAGE)

            writeUnlock(
                session,
                writeCharacteristic,
                notifyCharacteristic,
                token,
                encryptKey,
                passwordHex,
            )
        } catch (error: TimeoutCancellationException) {
            Log.e(TAG, "Unlock timed out", error)
            UnlockResult.Failure(CONNECT_TIMEOUT_MESSAGE)
        } catch (error: Exception) {
            Log.e(TAG, "Unlock failed", error)
            UnlockResult.Failure(error.message ?: "Unlock failed")
        } finally {
            session.releaseGatt(notifyCharacteristic)
        }
    }

    @SuppressLint("MissingPermission")
    private suspend fun performHandshake(
        session: GattSession,
        writeCharacteristic: BluetoothGattCharacteristic,
        notifyCharacteristic: BluetoothGattCharacteristic,
        encryptKey: String,
    ): String? {
        repeat(MAX_HANDSHAKE_ATTEMPTS) { attempt ->
            if (attempt > 0) {
                delay(400)
                session.flushNotifyBuffer(notifyCharacteristic)
                delay(200)
            }

            val response = session.writeEncryptedAndAwaitNotify(
                writeCharacteristic = writeCharacteristic,
                notifyCharacteristic = notifyCharacteristic,
                frameHex = LockProtocol.tokenRequestFrameHex(),
                encryptKey = encryptKey,
            ) ?: return@repeat

            val token = LockCrypto.parseTokenFromNotify(response, encryptKey)
            if (!token.isNullOrBlank()) {
                Log.d(TAG, "Handshake token=$token")
                return token
            }
            Log.w(TAG, "Handshake attempt ${attempt + 1}: notify received but token parse failed")
        }
        return null
    }

    @SuppressLint("MissingPermission")
    private suspend fun writeUnlock(
        session: GattSession,
        writeCharacteristic: BluetoothGattCharacteristic,
        notifyCharacteristic: BluetoothGattCharacteristic,
        token: String,
        encryptKey: String,
        passwordHex: String,
    ): UnlockResult {
        val unlockFrameHex = LockProtocol.unlockFrameHex(
            token,
            passwordHex = passwordHex,
        )
        val response = session.writeEncryptedAndAwaitNotify(
            writeCharacteristic = writeCharacteristic,
            notifyCharacteristic = notifyCharacteristic,
            frameHex = unlockFrameHex,
            encryptKey = encryptKey,
            timeoutMs = UNLOCK_NOTIFY_TIMEOUT_MS,
        )

        if (response != null) {
            val decrypted = LockCrypto.tryDecryptNotifyCandidates(
                response,
                encryptKey,
                isValidFrame = LockProtocol::isPasswordCommandAck,
            )
            if (LockProtocol.isPasswordCommandAck(decrypted)) {
                Log.d(TAG, "Unlock ack received")
                return UnlockResult.Success
            }
        }

        Log.d(TAG, "Unlock write completed")
        return UnlockResult.Success
    }

    private fun findWriteCharacteristic(
        services: List<android.bluetooth.BluetoothGattService>,
    ): BluetoothGattCharacteristic? {
        val lockService = services.firstOrNull { it.uuid == LockProtocol.LOCK_SERVICE_UUID }
            ?: return null
        return lockService.characteristics.firstOrNull { characteristic ->
            characteristic.uuid == LockProtocol.LOCK_WRITE_CHARACTERISTIC_UUID &&
                characteristic.properties and BluetoothGattCharacteristic.PROPERTY_WRITE != 0
        }
    }

    private fun findNotifyCharacteristic(
        services: List<android.bluetooth.BluetoothGattService>,
    ): BluetoothGattCharacteristic? {
        val lockService = services.firstOrNull { it.uuid == LockProtocol.LOCK_SERVICE_UUID }
            ?: return null
        return lockService.characteristics.firstOrNull { characteristic ->
            characteristic.uuid == LockProtocol.LOCK_NOTIFY_CHARACTERISTIC_UUID &&
                (
                    characteristic.properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY != 0 ||
                        characteristic.properties and BluetoothGattCharacteristic.PROPERTY_INDICATE != 0
                    )
        }
    }

    private fun normalizeMacAddress(macAddress: String): String {
        val compact = macAddress.replace(":", "").replace("-", "").uppercase()
        require(compact.length == 12) { "Invalid MAC address: $macAddress" }
        return compact.chunked(2).joinToString(":")
    }

    private class GattSession(context: Context) {
        private val appContext = context.applicationContext
        private var gatt: BluetoothGatt? = null
        private var connectedDeferred: CompletableDeferred<Unit>? = null
        private var servicesDeferred: CompletableDeferred<List<android.bluetooth.BluetoothGattService>>? = null
        private var descriptorDeferred: CompletableDeferred<Unit>? = null
        private var writeDeferred: CompletableDeferred<Unit>? = null
        private var notifyDeferred: CompletableDeferred<ByteArray>? = null
        private var notifyCharacteristicId: UUID? = null

        private val callback = object : BluetoothGattCallback() {
            override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
                if (newState == BluetoothProfile.STATE_CONNECTED) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                        gatt.requestConnectionPriority(BluetoothGatt.CONNECTION_PRIORITY_HIGH)
                    }
                    connectedDeferred?.complete(Unit)
                } else if (newState == BluetoothProfile.STATE_DISCONNECTED &&
                    connectedDeferred?.isCompleted == false
                ) {
                    connectedDeferred?.completeExceptionally(
                        IllegalStateException("Disconnected (status=$status)"),
                    )
                }
            }

            override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    servicesDeferred?.complete(gatt.services)
                } else {
                    servicesDeferred?.completeExceptionally(
                        IllegalStateException("Service discovery failed (status=$status)"),
                    )
                }
            }

            override fun onDescriptorWrite(
                gatt: BluetoothGatt,
                descriptor: BluetoothGattDescriptor,
                status: Int,
            ) {
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    descriptorDeferred?.complete(Unit)
                } else if (descriptorDeferred?.isCompleted == false) {
                    descriptorDeferred?.completeExceptionally(
                        IllegalStateException("Descriptor write failed (status=$status)"),
                    )
                }
            }

            @Deprecated("Deprecated in API 33")
            override fun onCharacteristicChanged(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
            ) {
                @Suppress("DEPRECATION")
                handleNotify(characteristic, characteristic.value ?: byteArrayOf())
            }

            override fun onCharacteristicChanged(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                value: ByteArray,
            ) {
                handleNotify(characteristic, value)
            }

            override fun onCharacteristicWrite(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                status: Int,
            ) {
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    writeDeferred?.complete(Unit)
                } else if (writeDeferred?.isCompleted == false) {
                    writeDeferred?.completeExceptionally(
                        IllegalStateException("Characteristic write failed (status=$status)"),
                    )
                }
            }

            private fun handleNotify(
                characteristic: BluetoothGattCharacteristic,
                value: ByteArray,
            ) {
                if (characteristic.uuid == notifyCharacteristicId &&
                    notifyDeferred?.isCompleted == false &&
                    value.isNotEmpty()
                ) {
                    Log.d(TAG, "Notify ${value.size}b from ${characteristic.uuid}")
                    notifyDeferred?.complete(value)
                }
            }
        }

        @SuppressLint("MissingPermission")
        suspend fun connect(device: BluetoothDevice) {
            connectedDeferred = CompletableDeferred()
            gatt = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                device.connectGatt(appContext, false, callback, BluetoothDevice.TRANSPORT_LE)
            } else {
                device.connectGatt(appContext, false, callback)
            } ?: throw IllegalStateException("connectGatt returned null")

            withTimeout(CONNECT_TIMEOUT_MS) {
                connectedDeferred?.await()
            }
        }

        @SuppressLint("MissingPermission")
        suspend fun discoverServices(): List<android.bluetooth.BluetoothGattService> {
            val activeGatt = gatt ?: throw IllegalStateException("GATT not connected")
            servicesDeferred = CompletableDeferred()

            if (!activeGatt.discoverServices()) {
                throw IllegalStateException("discoverServices returned false")
            }

            return withTimeout(SERVICE_DISCOVERY_TIMEOUT_MS) {
                servicesDeferred?.await() ?: emptyList()
            }
        }

        @SuppressLint("MissingPermission")
        suspend fun enableNotifications(notifyCharacteristic: BluetoothGattCharacteristic) {
            val activeGatt = gatt ?: throw IllegalStateException("GATT not connected")
            notifyCharacteristicId = notifyCharacteristic.uuid
            activeGatt.setCharacteristicNotification(notifyCharacteristic, true)

            val descriptor = notifyCharacteristic.getDescriptor(CCCD_UUID)
                ?: throw IllegalStateException("CCCD descriptor missing")

            descriptorDeferred = CompletableDeferred()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                activeGatt.writeDescriptor(
                    descriptor,
                    BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE,
                )
            } else {
                @Suppress("DEPRECATION")
                descriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                @Suppress("DEPRECATION")
                activeGatt.writeDescriptor(descriptor)
            }

            withTimeout(HANDSHAKE_TIMEOUT_MS) {
                descriptorDeferred?.await()
            }
        }

        @SuppressLint("MissingPermission")
        suspend fun flushNotifyBuffer(notifyCharacteristic: BluetoothGattCharacteristic) {
            val activeGatt = gatt ?: return
            try {
                activeGatt.setCharacteristicNotification(notifyCharacteristic, false)
                delay(150)
                activeGatt.setCharacteristicNotification(notifyCharacteristic, true)
                val descriptor = notifyCharacteristic.getDescriptor(CCCD_UUID) ?: return
                descriptorDeferred = CompletableDeferred()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    activeGatt.writeDescriptor(
                        descriptor,
                        BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE,
                    )
                } else {
                    @Suppress("DEPRECATION")
                    descriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                    @Suppress("DEPRECATION")
                    activeGatt.writeDescriptor(descriptor)
                }
                withTimeout(HANDSHAKE_TIMEOUT_MS) {
                    descriptorDeferred?.await()
                }
            } catch (error: Exception) {
                Log.w(TAG, "Notify flush warning: ${error.message}")
            }
        }

        @SuppressLint("MissingPermission")
        suspend fun writeEncryptedAndAwaitNotify(
            writeCharacteristic: BluetoothGattCharacteristic,
            notifyCharacteristic: BluetoothGattCharacteristic,
            frameHex: String,
            encryptKey: String,
            timeoutMs: Long = HANDSHAKE_TIMEOUT_MS,
        ): ByteArray? {
            val activeGatt = gatt ?: throw IllegalStateException("GATT not connected")
            val encrypted = LockCrypto.encrypt(frameHex, encryptKey)
                ?: throw IllegalStateException("Failed to encrypt BLE frame")

            notifyCharacteristicId = notifyCharacteristic.uuid
            notifyDeferred = CompletableDeferred()
            writeDeferred = CompletableDeferred()

            writeCharacteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                activeGatt.writeCharacteristic(
                    writeCharacteristic,
                    encrypted,
                    writeCharacteristic.writeType,
                )
            } else {
                @Suppress("DEPRECATION")
                writeCharacteristic.value = encrypted
                @Suppress("DEPRECATION")
                activeGatt.writeCharacteristic(writeCharacteristic)
            }

            withTimeout(HANDSHAKE_TIMEOUT_MS) {
                writeDeferred?.await()
            }

            return try {
                withTimeout(timeoutMs) {
                    notifyDeferred?.await()
                }
            } catch (_: TimeoutCancellationException) {
                Log.w(TAG, "Timed out waiting for notify after write")
                null
            }
        }

        @SuppressLint("MissingPermission")
        fun releaseGatt(notifyCharacteristic: BluetoothGattCharacteristic?) {
            val activeGatt = gatt ?: return

            notifyCharacteristic?.let { characteristic ->
                try {
                    activeGatt.setCharacteristicNotification(characteristic, false)
                    val descriptor = characteristic.getDescriptor(CCCD_UUID) ?: return@let
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        activeGatt.writeDescriptor(
                            descriptor,
                            BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE,
                        )
                    } else {
                        @Suppress("DEPRECATION")
                        descriptor.value = BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE
                        @Suppress("DEPRECATION")
                        activeGatt.writeDescriptor(descriptor)
                    }
                } catch (error: Exception) {
                    Log.w(TAG, "Failed to disable notifications before GATT teardown", error)
                }
            }

            try {
                activeGatt.disconnect()
                Log.d(TAG, "GATT disconnected")
            } catch (error: Exception) {
                Log.w(TAG, "GATT disconnect failed", error)
            }

            try {
                activeGatt.close()
                Log.d(TAG, "GATT closed")
            } catch (error: Exception) {
                Log.w(TAG, "GATT close failed", error)
            }

            gatt = null
        }
    }

    companion object {
        private const val TAG = "WearLockBle"
        private val CCCD_UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
        private const val CONNECT_TIMEOUT_MS = 15_000L
        private const val SERVICE_DISCOVERY_TIMEOUT_MS = 10_000L
        private const val HANDSHAKE_TIMEOUT_MS = 5_000L
        private const val UNLOCK_NOTIFY_TIMEOUT_MS = 3_000L
        private const val MAX_HANDSHAKE_ATTEMPTS = 3
        private const val CONNECT_TIMEOUT_MESSAGE =
            "Could not reach lock. Move closer and close Vigo Vault on your phone."
        private const val HANDSHAKE_FAILED_MESSAGE =
            "Handshake failed. Try again near the lock."
    }
}
