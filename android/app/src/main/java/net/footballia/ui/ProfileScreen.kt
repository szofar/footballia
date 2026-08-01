package net.footballia.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.*
import net.footballia.viewmodel.FootballiaViewModel

/** Minimal account tab: who's signed in, Master entitlement, and sign out. Mirrors ProfileView.swift. */
@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
fun ProfileScreen(viewModel: FootballiaViewModel) {
    var confirmingLogout by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 28.dp, vertical = 28.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp)
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("Profile", color = Color.White, fontSize = 24.sp, fontWeight = FontWeight.Bold)
            Text("Account and access", color = Color.White.copy(alpha = 0.35f), fontSize = 13.sp)
        }

        // Account
        ProfileCard {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                Icon(
                    Icons.Default.AccountCircle,
                    contentDescription = null,
                    tint = Color(0xFF22C55E).copy(alpha = 0.8f),
                    modifier = Modifier.size(40.dp)
                )
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        viewModel.accountEmail ?: "Signed in",
                        color = Color.White,
                        fontSize = 15.sp,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1
                    )
                    Text("footballia.eu", color = Color.White.copy(alpha = 0.35f), fontSize = 12.sp)
                }
            }
        }

        // Master status
        val master = viewModel.hasMasterAccess
        ProfileCard {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Icon(
                        if (master == true) Icons.Default.Star else Icons.Default.Lock,
                        contentDescription = null,
                        tint = if (master == true) Color(0xFF22C55E) else Color.White.copy(alpha = 0.3f),
                        modifier = Modifier.size(18.dp)
                    )
                    Text(
                        if (master == true) "Master access" else "No Master access",
                        color = Color.White,
                        fontSize = 15.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                    if (master == null) {
                        Spacer(Modifier.weight(1f))
                        CircularProgressIndicator(
                            modifier = Modifier.size(16.dp),
                            color = Color(0xFF22C55E),
                            strokeWidth = 2.dp
                        )
                    }
                }
                Text(
                    if (master == true)
                        "Master features such as the Calendar are unlocked on this account."
                    else
                        "The Calendar is a Master feature. Visit footballia.eu/master in a browser to subscribe, then reopen the app.",
                    color = Color.White.copy(alpha = 0.4f),
                    fontSize = 12.sp
                )
            }
        }

        // Sign out
        var signOutFocused by remember { mutableStateOf(false) }
        Surface(
            onClick = {
                if (confirmingLogout) viewModel.logout() else confirmingLogout = true
            },
            modifier = Modifier.onFocusChanged { signOutFocused = it.isFocused },
            shape = ClickableSurfaceDefaults.shape(shape = RoundedCornerShape(10.dp)),
            scale = ClickableSurfaceDefaults.scale(focusedScale = 1.02f),
            colors = ClickableSurfaceDefaults.colors(
                containerColor = if (confirmingLogout) Color(0xFFB91C1C) else Color.White.copy(alpha = 0.08f),
                contentColor = Color.White,
                focusedContainerColor = Color(0xFFDC2626),
                focusedContentColor = Color.White
            )
        ) {
            Text(
                if (confirmingLogout) "Press again to confirm" else "Sign Out",
                color = when {
                    confirmingLogout || signOutFocused -> Color.White
                    else -> Color(0xFFF87171)
                },
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(horizontal = 24.dp, vertical = 12.dp)
            )
        }
    }
}

@Composable
private fun ProfileCard(content: @Composable () -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .widthIn(max = 640.dp)
            .background(Color(0xFF1E1E24), RoundedCornerShape(12.dp))
            .padding(16.dp)
    ) {
        content()
    }
}
