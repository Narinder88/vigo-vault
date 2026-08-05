package com.singh.fitnessssnacklock.wear.ui

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.CircularProgressIndicator
import androidx.wear.compose.material.Text
import com.singh.fitnessssnacklock.wear.R
import kotlinx.coroutines.delay

private val TrueBlack = Color(0xFF000000)
private val AccentGreen = Color(0xFF00E676)

@Composable
fun UnlockScreen(
    viewModel: UnlockViewModel = viewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val context = LocalContext.current

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions(),
    ) { grants ->
        val allGranted = grants.values.all { it }
        if (allGranted) {
            viewModel.unlock()
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
                viewModel.unlock()
            } else {
                permissionLauncher.launch(
                    arrayOf(
                        Manifest.permission.BLUETOOTH_CONNECT,
                        Manifest.permission.BLUETOOTH_SCAN,
                    ),
                )
            }
        } else {
            viewModel.unlock()
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

    WearLockTheme {
        when {
            uiState.lockConfig != null -> {
                val statusLabel = when (val status = uiState.statusMessage) {
                    UnlockStatus.NoLockConfigured ->
                        stringResource(R.string.no_lock_configured)

                    UnlockStatus.PermissionRequired ->
                        stringResource(R.string.bluetooth_permission_required)

                    UnlockStatus.Ready ->
                        stringResource(R.string.unlock)

                    UnlockStatus.Unlocking ->
                        stringResource(R.string.unlocking)

                    UnlockStatus.Success ->
                        stringResource(R.string.unlock_success)

                    is UnlockStatus.Failure ->
                        status.message.ifBlank {
                            stringResource(R.string.unlock_failed)
                        }
                }

                LockControlScreen(
                    statusLabel = statusLabel,
                    isUnlocking = uiState.isUnlocking,
                    enabled = !uiState.isUnlocking,
                    onUnlockClick = { requestUnlock() },
                )
            }

            else -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(TrueBlack)
                        .padding(16.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Text(
                            text = stringResource(R.string.no_lock_configured),
                            color = Color.White.copy(alpha = 0.88f),
                            fontSize = 12.sp,
                            textAlign = TextAlign.Center,
                        )
                        if (uiState.isRefreshing) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(32.dp),
                                indicatorColor = AccentGreen,
                            )
                            Text(
                                text = stringResource(R.string.syncing),
                                color = AccentGreen,
                                fontSize = 11.sp,
                                textAlign = TextAlign.Center,
                            )
                        } else {
                            Button(onClick = { viewModel.refreshConfig() }) {
                                Text(text = stringResource(R.string.refresh))
                            }
                        }
                    }
                }
            }
        }
    }
}
