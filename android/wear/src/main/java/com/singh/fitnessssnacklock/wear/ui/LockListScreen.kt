package com.singh.fitnessssnacklock.wear.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.ui.res.painterResource
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.wear.compose.foundation.rotary.RotaryScrollableDefaults
import androidx.wear.compose.foundation.rotary.rotaryScrollable
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.Chip
import androidx.wear.compose.material.ChipDefaults
import androidx.wear.compose.material.CircularProgressIndicator
import androidx.wear.compose.material.Icon
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.PositionIndicator
import androidx.wear.compose.material.Scaffold
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.TimeText
import androidx.wear.compose.material.scrollAway
import com.singh.fitnessssnacklock.wear.R
import com.singh.fitnessssnacklock.wear.data.SyncedLock

private val AccentGreen = Color(0xFF00E676)
private val ChipBackground = Color(0xFF202124)
private val PinnedChipBackground = Color(0xFF14352A)
private val SubtitleColor = Color(0xFF9AA0A6)
private val LowBatteryRed = Color(0xFFE53935)
private val LowBatteryBackground = Color(0xFF3A1214)

@Composable
fun EmptyLocksScreen(
    viewModel: UnlockViewModel,
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val listState = rememberScalingLazyListState()

    Scaffold(
        timeText = { TimeText() },
        positionIndicator = { PositionIndicator(scalingLazyListState = listState) },
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 16.dp, vertical = 28.dp),
            contentAlignment = Alignment.Center,
        ) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Text(
                    text = stringResource(R.string.no_locks_synced),
                    color = Color.White.copy(alpha = 0.9f),
                    fontSize = 13.sp,
                    textAlign = TextAlign.Center,
                )
                if (uiState.isRefreshing) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(28.dp),
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

@Composable
fun LockListScreen(
    locks: List<SyncedLock>,
    onLockSelected: (SyncedLock) -> Unit,
) {
    val ordered = remember(locks) { sortPinnedFirst(locks) }
    val listState = rememberScalingLazyListState()
    val focusRequester = remember { FocusRequester() }
    val rotaryBehavior = RotaryScrollableDefaults.behavior(scrollableState = listState)

    LaunchedEffect(Unit) {
        focusRequester.requestFocus()
    }

    Scaffold(
        timeText = { TimeText(modifier = Modifier.scrollAway(listState)) },
        positionIndicator = { PositionIndicator(scalingLazyListState = listState) },
    ) {
        ScalingLazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .rotaryScrollable(
                    behavior = rotaryBehavior,
                    focusRequester = focusRequester,
                )
                .focusRequester(focusRequester)
                .focusable(),
            state = listState,
            autoCentering = null,
            contentPadding = PaddingValues(
                top = 32.dp,
                bottom = 28.dp,
                start = 10.dp,
                end = 10.dp,
            ),
        ) {
            items(
                count = ordered.size,
                key = { index -> ordered[index].id },
            ) { index ->
                val lock = ordered[index]
                LockRow(
                    lock = lock,
                    onClick = { onLockSelected(lock) },
                )
            }
        }
    }
}

@Composable
private fun LockRow(
    lock: SyncedLock,
    onClick: () -> Unit,
) {
    val lowBattery = isLowBattery(lock.batteryLevel)
    val subtitle = if (lowBattery) {
        stringResource(R.string.low_battery, lock.batteryLevel ?: 0)
    } else {
        lockSubtitle(lock)
    }
    val colors = ChipDefaults.secondaryChipColors(
        backgroundColor = when {
            lowBattery -> LowBatteryBackground
            lock.isPinned -> PinnedChipBackground
            else -> ChipBackground
        },
        contentColor = Color.White,
        secondaryContentColor = if (lowBattery) LowBatteryRed else SubtitleColor,
        iconColor = LowBatteryRed,
    )
    val border = if (lowBattery) {
        ChipDefaults.chipBorder(
            borderStroke = BorderStroke(1.5.dp, LowBatteryRed),
        )
    } else {
        ChipDefaults.chipBorder()
    }
    if (subtitle == null) {
        Chip(
            modifier = Modifier.fillMaxWidth(),
            onClick = onClick,
            colors = colors,
            border = border,
            icon = if (!lowBattery) null else {
                { LowBatteryIcon() }
            },
            label = {
                Text(
                    text = lock.displayName,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            },
        )
    } else {
        Chip(
            modifier = Modifier.fillMaxWidth(),
            onClick = onClick,
            colors = colors,
            border = border,
            icon = if (!lowBattery) null else {
                { LowBatteryIcon() }
            },
            label = {
                Text(
                    text = lock.displayName,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            },
            secondaryLabel = {
                Text(
                    text = subtitle,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            },
        )
    }
}

@Composable
private fun LowBatteryIcon() {
    Icon(
        painter = painterResource(R.drawable.ic_battery_warning),
        contentDescription = null,
        tint = LowBatteryRed,
        modifier = Modifier.size(18.dp),
    )
}

private fun lockSubtitle(lock: SyncedLock): String? {
    val level = lock.batteryLevel
    val name = lock.advName.trim()
    val percent = level?.let { "$it%" }
    return when {
        name.isNotEmpty() && percent != null -> "$name • $percent"
        name.isNotEmpty() -> name
        percent != null -> percent
        else -> null
    }
}

private fun isLowBattery(level: Int?): Boolean = level != null && level in 1..20

private fun sortPinnedFirst(locks: List<SyncedLock>): List<SyncedLock> {
    val pinned = ArrayList<SyncedLock>()
    val unpinned = ArrayList<SyncedLock>()
    for (lock in locks) {
        if (lock.isPinned) pinned.add(lock) else unpinned.add(lock)
    }
    return pinned + unpinned
}
