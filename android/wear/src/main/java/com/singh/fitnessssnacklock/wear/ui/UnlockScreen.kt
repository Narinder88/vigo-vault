package com.singh.fitnessssnacklock.wear.ui

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.CircularProgressIndicator
import androidx.wear.compose.material.Text
import com.singh.fitnessssnacklock.wear.R
import kotlinx.coroutines.delay

@Composable
fun UnlockScreen(
    viewModel: UnlockViewModel = viewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val context = LocalContext.current

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        if (granted) {
            viewModel.unlock()
        }
    }

    fun requestUnlock() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val granted = ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.BLUETOOTH_CONNECT,
            ) == PackageManager.PERMISSION_GRANTED
            if (granted) {
                viewModel.unlock()
            } else {
                permissionLauncher.launch(Manifest.permission.BLUETOOTH_CONNECT)
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
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(16.dp),
            contentAlignment = Alignment.Center,
        ) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically),
            ) {
                when {
                    uiState.isUnlocking -> {
                        CircularProgressIndicator(
                            modifier = Modifier.size(48.dp),
                        )
                        Text(
                            text = stringResource(R.string.unlocking),
                            textAlign = TextAlign.Center,
                        )
                    }

                    uiState.lockConfig == null -> {
                        Text(
                            text = stringResource(R.string.no_lock_configured),
                            textAlign = TextAlign.Center,
                        )
                    }

                    else -> {
                        Button(
                            onClick = { requestUnlock() },
                            enabled = !uiState.isUnlocking,
                        ) {
                            Text(text = stringResource(R.string.unlock))
                        }

                        val statusText = when (val status = uiState.statusMessage) {
                            UnlockStatus.NoLockConfigured ->
                                stringResource(R.string.no_lock_configured)

                            UnlockStatus.PermissionRequired ->
                                stringResource(R.string.bluetooth_permission_required)

                            UnlockStatus.Ready -> null

                            UnlockStatus.Unlocking ->
                                stringResource(R.string.unlocking)

                            UnlockStatus.Success ->
                                stringResource(R.string.unlock_success)

                            is UnlockStatus.Failure ->
                                status.message.ifBlank {
                                    stringResource(R.string.unlock_failed)
                                }
                        }

                        if (statusText != null) {
                            Text(
                                text = statusText,
                                textAlign = TextAlign.Center,
                            )
                        }
                    }
                }
            }
        }
    }
}
