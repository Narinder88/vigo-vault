package com.singh.fitnessssnacklock.wear.ui

import android.app.Application
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.singh.fitnessssnacklock.wear.ble.LockBleClient
import com.singh.fitnessssnacklock.wear.data.LockConfig
import com.singh.fitnessssnacklock.wear.data.LockConfigRepository
import com.singh.fitnessssnacklock.wear.data.LockConfigSync
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class UnlockViewModel(application: Application) : AndroidViewModel(application) {
    private val repository = LockConfigRepository.getInstance(application)
    private val configSync = LockConfigSync(application)
    private val bleClient = LockBleClient(application)

    private val _uiState = MutableStateFlow(UnlockUiState())
    val uiState: StateFlow<UnlockUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            configSync.refreshFromDataLayer()
        }

        viewModelScope.launch {
            repository.lockConfig.collect { config ->
                _uiState.update { current ->
                    current.copy(
                        lockConfig = config,
                        statusMessage = if (config == null) {
                            UnlockStatus.NoLockConfigured
                        } else {
                            UnlockStatus.Ready
                        },
                    )
                }
            }
        }
    }

    fun refreshConfig() {
        if (_uiState.value.isRefreshing) return

        viewModelScope.launch {
            _uiState.update { it.copy(isRefreshing = true) }
            configSync.refreshFromDataLayer()
            _uiState.update { it.copy(isRefreshing = false) }
        }
    }

    fun unlock() {
        val config = repository.lockConfig.value
        if (config == null) {
            _uiState.update {
                it.copy(statusMessage = UnlockStatus.NoLockConfigured)
            }
            return
        }

        if (!hasBluetoothPermission()) {
            _uiState.update {
                it.copy(statusMessage = UnlockStatus.PermissionRequired)
            }
            return
        }

        if (_uiState.value.isUnlocking) return

        viewModelScope.launch {
            _uiState.update {
                it.copy(isUnlocking = true, statusMessage = UnlockStatus.Unlocking)
            }

            when (
                val result = bleClient.connectAndUnlock(
                    macAddress = config.macAddress,
                    secretKey = config.secretKey,
                )
            ) {
                is LockBleClient.UnlockResult.Success -> {
                    _uiState.update {
                        it.copy(
                            isUnlocking = false,
                            statusMessage = UnlockStatus.Success,
                        )
                    }
                }

                is LockBleClient.UnlockResult.Failure -> {
                    _uiState.update {
                        it.copy(
                            isUnlocking = false,
                            statusMessage = UnlockStatus.Failure(result.message),
                        )
                    }
                }
            }
        }
    }

    fun clearTransientStatus() {
        val config = repository.lockConfig.value
        _uiState.update {
            it.copy(
                statusMessage = if (config == null) {
                    UnlockStatus.NoLockConfigured
                } else {
                    UnlockStatus.Ready
                },
            )
        }
    }

    private fun hasBluetoothPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return true
        }
        val connectGranted = ContextCompat.checkSelfPermission(
            getApplication(),
            android.Manifest.permission.BLUETOOTH_CONNECT,
        ) == PackageManager.PERMISSION_GRANTED
        val scanGranted = ContextCompat.checkSelfPermission(
            getApplication(),
            android.Manifest.permission.BLUETOOTH_SCAN,
        ) == PackageManager.PERMISSION_GRANTED
        return connectGranted && scanGranted
    }
}

data class UnlockUiState(
    val lockConfig: LockConfig? = null,
    val isUnlocking: Boolean = false,
    val isRefreshing: Boolean = false,
    val statusMessage: UnlockStatus = UnlockStatus.NoLockConfigured,
)

sealed class UnlockStatus {
    data object NoLockConfigured : UnlockStatus()
    data object PermissionRequired : UnlockStatus()
    data object Ready : UnlockStatus()
    data object Unlocking : UnlockStatus()
    data object Success : UnlockStatus()
    data class Failure(val message: String) : UnlockStatus()
}
