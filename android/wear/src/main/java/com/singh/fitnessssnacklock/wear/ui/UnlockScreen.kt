package com.singh.fitnessssnacklock.wear.ui

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.PositionIndicator
import androidx.wear.compose.material.Scaffold
import androidx.wear.compose.material.TimeText
import com.singh.fitnessssnacklock.wear.R
import com.singh.fitnessssnacklock.wear.data.SyncedLock
import kotlinx.coroutines.delay

@Composable
fun UnlockScreen(
    lock: SyncedLock,
    viewModel: UnlockViewModel,
    readyLabel: String? = null,
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val listState = rememberScalingLazyListState()
    val resolvedReadyLabel = readyLabel ?: stringResource(R.string.unlock)

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions(),
    ) { grants ->
        if (grants.values.all { it }) {
            viewModel.unlock(lock.id)
        }
    }

    fun requestUnlock() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val connectGranted = ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.BLUETOOTH_CONNECT,
            ) == PackageManager.PERMISSION_GRANTED
            val scanGranted = ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.BLUETOOTH_SCAN,
            ) == PackageManager.PERMISSION_GRANTED
            if (connectGranted && scanGranted) {
                viewModel.unlock(lock.id)
            } else {
                permissionLauncher.launch(
                    arrayOf(
                        Manifest.permission.BLUETOOTH_CONNECT,
                        Manifest.permission.BLUETOOTH_SCAN,
                    ),
                )
            }
        } else {
            viewModel.unlock(lock.id)
        }
    }

    LaunchedEffect(Unit) {
        viewModel.refreshConfig()
    }

    LaunchedEffect(uiState.statusMessage) {
        if (uiState.statusMessage is UnlockStatus.Success ||
            uiState.statusMessage is UnlockStatus.Failure
        ) {
            delay(2_000)
            viewModel.clearTransientStatus()
        }
    }

    val statusLabel = when (val status = uiState.statusMessage) {
        UnlockStatus.NoLockConfigured ->
            stringResource(R.string.no_locks_synced)

        UnlockStatus.PermissionRequired ->
            stringResource(R.string.bluetooth_permission_required)

        UnlockStatus.Ready -> resolvedReadyLabel

        UnlockStatus.Unlocking ->
            stringResource(R.string.unlocking)

        UnlockStatus.Success ->
            stringResource(R.string.unlock_success)

        is UnlockStatus.Failure ->
            status.message.ifBlank {
                stringResource(R.string.unlock_failed)
            }
    }

    Scaffold(
        timeText = { TimeText() },
        positionIndicator = { PositionIndicator(scalingLazyListState = listState) },
    ) {
        LockControlScreen(
            statusLabel = statusLabel,
            lockName = lock.displayName,
            batteryLevel = lock.batteryLevel,
            isUnlocking = uiState.isUnlocking,
            enabled = !uiState.isUnlocking,
            onUnlockClick = { requestUnlock() },
        )
    }
}
