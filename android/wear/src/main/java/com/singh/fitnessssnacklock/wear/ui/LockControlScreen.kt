package com.singh.fitnessssnacklock.wear.ui

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.CircularProgressIndicator
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.Text
import com.singh.fitnessssnacklock.wear.R
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.PI

private val TrueBlack = Color(0xFF000000)
private val AccentGreen = Color(0xFF00E676)
private val BezelGray = Color(0xFFB8B8B8)

@Composable
fun LockControlScreen(
    statusLabel: String,
    isUnlocking: Boolean,
    enabled: Boolean,
    onUnlockClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier
            .fillMaxSize()
            .background(TrueBlack),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            modifier = Modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            BoxWithConstraints(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxSize(),
                contentAlignment = Alignment.Center,
            ) {
                val discSize = minOf(maxWidth, maxHeight) * 0.86f

                LockControlDisc(
                    discSize = discSize,
                    isUnlocking = isUnlocking,
                    enabled = enabled,
                    onUnlockClick = onUnlockClick,
                )
            }

            Text(
                text = statusLabel,
                color = if (isUnlocking) AccentGreen else Color.White.copy(alpha = 0.88f),
                fontSize = 11.sp,
                fontWeight = FontWeight.Medium,
                letterSpacing = 0.6.sp,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .padding(bottom = 14.dp)
                    .height(18.dp),
            )
        }
    }
}

@Composable
private fun LockControlDisc(
    discSize: Dp,
    isUnlocking: Boolean,
    enabled: Boolean,
    onUnlockClick: () -> Unit,
) {
    val interactionSource = remember { MutableInteractionSource() }
    val pulseTransition = rememberInfiniteTransition(label = "unlockPulse")
    val pulseScale = if (isUnlocking) {
        pulseTransition.animateFloat(
            initialValue = 0.96f,
            targetValue = 1.04f,
            animationSpec = infiniteRepeatable(
                animation = tween(durationMillis = 900, easing = FastOutSlowInEasing),
                repeatMode = RepeatMode.Reverse,
            ),
            label = "pulseScale",
        ).value
    } else {
        1f
    }

    Box(
        modifier = Modifier
            .size(discSize * 1.08f)
            .scale(pulseScale)
            .clickable(
                interactionSource = interactionSource,
                indication = null,
                enabled = enabled && !isUnlocking,
                onClick = onUnlockClick,
            ),
        contentAlignment = Alignment.Center,
    ) {
        GreenGlowRing(
            modifier = Modifier.size(discSize * 1.06f),
        )

        SteelBrushDisc(
            modifier = Modifier
                .size(discSize)
                .clip(CircleShape),
        )

        InnerBezelRing(
            modifier = Modifier.size(discSize * 0.74f),
        )

        if (isUnlocking) {
            CircularProgressIndicator(
                modifier = Modifier.size(discSize * 0.28f),
                strokeWidth = 3.dp,
                indicatorColor = AccentGreen,
            )
        } else {
            Icon(
                painter = painterResource(R.drawable.ic_lock_open),
                contentDescription = null,
                tint = Color.White.copy(alpha = 0.94f),
                modifier = Modifier.size(discSize * 0.22f),
            )
        }
    }
}

@Composable
private fun GreenGlowRing(modifier: Modifier = Modifier) {
    Canvas(modifier = modifier) {
        val radius = size.minDimension / 2f
        drawCircle(
            brush = Brush.radialGradient(
                colors = listOf(
                    AccentGreen.copy(alpha = 0.95f),
                    AccentGreen.copy(alpha = 0.62f),
                    AccentGreen.copy(alpha = 0.28f),
                    AccentGreen.copy(alpha = 0.08f),
                    Color.Transparent,
                ),
                center = center,
                radius = radius,
            ),
            radius = radius,
            center = center,
        )
    }
}

@Composable
private fun SteelBrushDisc(modifier: Modifier = Modifier) {
    Canvas(modifier = modifier) {
        val radius = size.minDimension / 2f
        val centerPoint = center

        drawCircle(
            brush = steelSweepBrush(),
            radius = radius,
            center = centerPoint,
        )

        drawSteelBrushStreaks(radius = radius, centerPoint = centerPoint)

        drawCircle(
            brush = Brush.radialGradient(
                colors = listOf(
                    Color.White.copy(alpha = 0.16f),
                    Color.Transparent,
                    Color.Black.copy(alpha = 0.42f),
                ),
                center = Offset(centerPoint.x - radius * 0.28f, centerPoint.y - radius * 0.32f),
                radius = radius * 1.05f,
            ),
            radius = radius,
            center = centerPoint,
        )

        drawCircle(
            color = Color.White.copy(alpha = 0.10f),
            radius = radius - 1.5f,
            center = centerPoint,
            style = Stroke(width = 1.5f),
        )
    }
}

@Composable
private fun InnerBezelRing(modifier: Modifier = Modifier) {
    Canvas(modifier = modifier) {
        drawCircle(
            color = BezelGray.copy(alpha = 0.55f),
            radius = size.minDimension / 2f,
            style = Stroke(width = 1.75f),
        )
    }
}

private fun DrawScope.steelSweepBrush(): Brush {
    return Brush.sweepGradient(
        0.00f to Color(0xFF1A1A1C),
        0.14f to Color(0xFF35353A),
        0.28f to Color(0xFF101012),
        0.42f to Color(0xFF4A4A50),
        0.56f to Color(0xFF18181B),
        0.70f to Color(0xFF3A3A40),
        0.84f to Color(0xFF121214),
        1.00f to Color(0xFF1A1A1C),
        center = center,
    )
}

private fun DrawScope.drawSteelBrushStreaks(
    radius: Float,
    centerPoint: Offset,
) {
    val streakCount = 220
    for (index in 0 until streakCount) {
        val angle = (index * (360.0 / streakCount) * PI / 180.0).toFloat()
        val streakAlpha = 0.018f + ((index % 7) * 0.0045f)
        val innerRadius = radius * 0.08f
        val outerRadius = radius * 0.98f

        val start = Offset(
            centerPoint.x + cos(angle) * innerRadius,
            centerPoint.y + sin(angle) * innerRadius,
        )
        val end = Offset(
            centerPoint.x + cos(angle) * outerRadius,
            centerPoint.y + sin(angle) * outerRadius,
        )

        val highlight = index % 11 == 0
        drawLine(
            color = if (highlight) {
                Color.White.copy(alpha = streakAlpha + 0.03f)
            } else {
                Color.Black.copy(alpha = streakAlpha + 0.01f)
            },
            start = start,
            end = end,
            strokeWidth = if (highlight) 1.6f else 1.1f,
            cap = StrokeCap.Round,
        )
    }

    for (ringIndex in 1..5) {
        val ringRadius = radius * (0.22f + ringIndex * 0.13f)
        rotate(8f * ringIndex) {
            drawCircle(
                brush = Brush.sweepGradient(
                    0.0f to Color.Transparent,
                    0.5f to Color.White.copy(alpha = 0.025f),
                    1.0f to Color.Transparent,
                    center = centerPoint,
                ),
                radius = ringRadius,
                center = centerPoint,
                style = Stroke(width = 0.8f),
            )
        }
    }
}
