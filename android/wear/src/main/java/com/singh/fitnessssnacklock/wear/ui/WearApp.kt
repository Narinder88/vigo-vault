package com.singh.fitnessssnacklock.wear.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.graphics.Color
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.wear.compose.navigation.SwipeDismissableNavHost
import androidx.wear.compose.navigation.composable
import androidx.wear.compose.navigation.rememberSwipeDismissableNavController

private object WearRoutes {
    const val HOME = "home"
    const val UNLOCK = "unlock"
}

@Composable
fun WearApp(
    viewModel: UnlockViewModel = viewModel(),
) {
    val locks by viewModel.locks.collectAsStateWithLifecycle()
    val selectedLockId by viewModel.selectedLockId.collectAsStateWithLifecycle()
    val navController = rememberSwipeDismissableNavController()

    LaunchedEffect(locks.size) {
        val route = navController.currentBackStackEntry?.destination?.route
        if (locks.size < 2 && route == WearRoutes.UNLOCK) {
            navController.popBackStack()
        }
    }

    WearLockTheme {
        SwipeDismissableNavHost(
            navController = navController,
            startDestination = WearRoutes.HOME,
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black),
        ) {
            composable(WearRoutes.HOME) {
                when {
                    locks.isEmpty() -> EmptyLocksScreen(viewModel = viewModel)
                    locks.size == 1 -> UnlockScreen(
                        lock = locks.first(),
                        viewModel = viewModel,
                    )
                    else -> LockListScreen(
                        locks = locks,
                        onLockSelected = { lock ->
                            viewModel.selectLock(lock.id)
                            navController.navigate(WearRoutes.UNLOCK)
                        },
                    )
                }
            }
            composable(WearRoutes.UNLOCK) {
                val lock = locks.firstOrNull { it.id == selectedLockId }
                if (lock == null) {
                    LaunchedEffect(selectedLockId, locks) {
                        navController.popBackStack()
                    }
                } else {
                    UnlockScreen(
                        lock = lock,
                        viewModel = viewModel,
                        readyLabel = lock.displayName,
                    )
                }
            }
        }
    }
}
