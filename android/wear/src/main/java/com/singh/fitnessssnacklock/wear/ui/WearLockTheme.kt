package com.singh.fitnessssnacklock.wear.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.wear.compose.material.MaterialTheme

private val PrimaryGreen = Color(0xFF00E676)
private val SurfaceDark = Color(0xFF000000)

@Composable
fun WearLockTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colors = androidx.wear.compose.material.Colors(
            primary = PrimaryGreen,
            primaryVariant = PrimaryGreen,
            secondary = PrimaryGreen,
            secondaryVariant = PrimaryGreen,
            background = SurfaceDark,
            surface = SurfaceDark,
            error = Color(0xFFCF6679),
            onPrimary = Color.White,
            onSecondary = Color.White,
            onBackground = Color.White,
            onSurface = Color.White,
            onError = Color.Black,
        ),
        content = content,
    )
}
