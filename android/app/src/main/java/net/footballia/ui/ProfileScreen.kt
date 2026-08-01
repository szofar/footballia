package net.footballia.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.*
import coil.compose.AsyncImage
import net.footballia.data.SearchSuggestion
import net.footballia.data.Team
import net.footballia.viewmodel.FootballiaViewModel

/**
 * Account tab: who's signed in, Master entitlement, the Favorite Teams editor, and sign out.
 * Mirrors ProfileView.swift.
 */
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

        // Favorite teams
        FavoriteTeamsSection(viewModel)

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

// MARK: - Favorite teams editor

/**
 * Editor for the favourites list that the Favorites page renders. Both read the same
 * ViewModel state, so add/remove/clear shows up on that page immediately and is persisted.
 */
@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
private fun FavoriteTeamsSection(viewModel: FootballiaViewModel) {
    var query by remember { mutableStateOf("") }
    var confirmingClear by remember { mutableStateOf(false) }

    // Debounced live search, matching the Search tab's behaviour.
    LaunchedEffect(query) {
        val q = query.trim()
        if (q.isEmpty()) { viewModel.clearFavoriteTeamSearch(); return@LaunchedEffect }
        kotlinx.coroutines.delay(300)
        viewModel.searchFavoriteTeamCandidates(q)
    }

    val favorites = viewModel.favoriteTeams

    ProfileCard {
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Icon(
                    Icons.Default.Star,
                    contentDescription = null,
                    tint = Color(0xFF22C55E),
                    modifier = Modifier.size(18.dp)
                )
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text("Favorite Teams", color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                    Text(
                        if (favorites.isEmpty()) "No teams — search below to add some"
                        else "${favorites.size} teams shown on the Favorites page",
                        color = Color.White.copy(alpha = 0.4f),
                        fontSize = 12.sp
                    )
                }
            }

            // Search bar
            BasicTextField(
                value = query,
                onValueChange = { query = it },
                singleLine = true,
                textStyle = TextStyle(color = Color.White, fontSize = 14.sp),
                cursorBrush = SolidColor(Color(0xFF22C55E)),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                keyboardActions = KeyboardActions(
                    onSearch = { viewModel.searchFavoriteTeamCandidates(query.trim()) }
                ),
                decorationBox = { inner ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(Color.White.copy(alpha = 0.07f), RoundedCornerShape(10.dp))
                            .padding(horizontal = 12.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        if (viewModel.isSearchingFavoriteTeams) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(16.dp),
                                color = Color(0xFF22C55E),
                                strokeWidth = 2.dp
                            )
                        } else {
                            Icon(
                                Icons.Default.Search,
                                contentDescription = null,
                                tint = Color.White.copy(alpha = 0.4f),
                                modifier = Modifier.size(16.dp)
                            )
                        }
                        Box(modifier = Modifier.weight(1f)) {
                            if (query.isEmpty()) {
                                Text(
                                    "Search teams to add…",
                                    color = Color.White.copy(alpha = 0.3f),
                                    fontSize = 14.sp
                                )
                            }
                            inner()
                        }
                        if (query.isNotEmpty()) {
                            IconButton(
                                onClick = { query = ""; viewModel.clearFavoriteTeamSearch() },
                                modifier = Modifier.size(20.dp)
                            ) {
                                Icon(Icons.Default.Clear, contentDescription = "Clear search", tint = Color.White.copy(alpha = 0.4f))
                            }
                        }
                    }
                },
                modifier = Modifier.fillMaxWidth()
            )

            // Search results
            if (query.isNotBlank()) {
                val error = viewModel.favoriteTeamSearchError
                when {
                    error != null -> SectionNote(error)
                    viewModel.favoriteTeamSearchResults.isEmpty() && viewModel.isSearchingFavoriteTeams ->
                        SectionNote("Searching…")
                    else -> Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        viewModel.favoriteTeamSearchResults.forEach { suggestion ->
                            SearchResultRow(
                                suggestion = suggestion,
                                isFavorite = viewModel.isFavorite(suggestion.slug),
                                isPending = suggestion.slug in viewModel.pendingFavoriteSlugs,
                                onAdd = { viewModel.addFavoriteTeam(suggestion) },
                                onRemove = {
                                    viewModel.favoriteTeams
                                        .firstOrNull { it.slug == suggestion.slug }
                                        ?.let(viewModel::removeFavoriteTeam)
                                }
                            )
                        }
                    }
                }
            }

            // Current list
            if (favorites.isNotEmpty()) {
                Text(
                    "YOUR LIST",
                    color = Color.White.copy(alpha = 0.3f),
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold
                )
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    favorites.forEach { team ->
                        FavoriteTeamRow(team = team) { viewModel.removeFavoriteTeam(team) }
                    }
                }
            }

            // List-wide actions
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                SmallActionButton(
                    text = if (confirmingClear) "Press again to confirm" else "Clear All",
                    icon = Icons.Default.Close,
                    enabled = favorites.isNotEmpty(),
                    destructive = true,
                    highlighted = confirmingClear
                ) {
                    if (confirmingClear) {
                        viewModel.clearFavoriteTeams()
                        confirmingClear = false
                    } else {
                        confirmingClear = true
                    }
                }
                SmallActionButton(
                    text = "Restore Defaults",
                    icon = Icons.Default.Refresh,
                    enabled = true,
                    destructive = false,
                    highlighted = false
                ) {
                    confirmingClear = false
                    viewModel.restoreDefaultFavoriteTeams()
                }
            }
        }
    }
}

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
private fun SearchResultRow(
    suggestion: SearchSuggestion,
    isFavorite: Boolean,
    isPending: Boolean,
    onAdd: () -> Unit,
    onRemove: () -> Unit
) {
    Surface(
        onClick = { if (!isPending) { if (isFavorite) onRemove() else onAdd() } },
        modifier = Modifier.fillMaxWidth(),
        shape = ClickableSurfaceDefaults.shape(RoundedCornerShape(8.dp)),
        colors = ClickableSurfaceDefaults.colors(
            containerColor = Color.Transparent,
            contentColor = Color.White,
            focusedContainerColor = Color.White.copy(alpha = 0.08f),
            focusedContentColor = Color.White
        )
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(suggestion.name, color = Color.White, fontSize = 14.sp, maxLines = 1, modifier = Modifier.weight(1f))
            when {
                isPending -> CircularProgressIndicator(
                    modifier = Modifier.size(14.dp),
                    color = Color(0xFF22C55E),
                    strokeWidth = 2.dp
                )
                isFavorite -> Row(
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Default.Check, contentDescription = null, tint = Color(0xFF22C55E), modifier = Modifier.size(14.dp))
                    Text("Added", color = Color(0xFF22C55E), fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                }
                else -> Row(
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Default.Add, contentDescription = null, tint = Color.White.copy(alpha = 0.55f), modifier = Modifier.size(14.dp))
                    Text("Add", color = Color.White.copy(alpha = 0.55f), fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }
}

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
private fun FavoriteTeamRow(team: Team, onRemove: () -> Unit) {
    Surface(
        onClick = onRemove,
        modifier = Modifier.fillMaxWidth(),
        shape = ClickableSurfaceDefaults.shape(RoundedCornerShape(8.dp)),
        colors = ClickableSurfaceDefaults.colors(
            containerColor = Color.White.copy(alpha = 0.04f),
            contentColor = Color.White,
            focusedContainerColor = Color.White.copy(alpha = 0.12f),
            focusedContentColor = Color.White
        )
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier
                    .size(28.dp)
                    .background(Color.White.copy(alpha = 0.08f), RoundedCornerShape(6.dp)),
                contentAlignment = Alignment.Center
            ) {
                if (team.logoUrl != null) {
                    AsyncImage(
                        model = team.logoUrl,
                        contentDescription = null,
                        contentScale = ContentScale.Fit,
                        modifier = Modifier.size(22.dp)
                    )
                } else {
                    Text(
                        team.name.take(2).uppercase(),
                        color = Color.White.copy(alpha = 0.4f),
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
            }
            Text(team.name, color = Color.White, fontSize = 14.sp, maxLines = 1, modifier = Modifier.weight(1f))
            Icon(
                Icons.Default.Close,
                contentDescription = "Remove ${team.name}",
                tint = Color(0xFFF87171).copy(alpha = 0.8f),
                modifier = Modifier.size(16.dp)
            )
        }
    }
}

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
private fun SmallActionButton(
    text: String,
    icon: ImageVector,
    enabled: Boolean,
    destructive: Boolean,
    highlighted: Boolean,
    onClick: () -> Unit
) {
    val accent = if (destructive) Color(0xFFF87171) else Color.White.copy(alpha = 0.7f)
    Surface(
        onClick = onClick,
        enabled = enabled,
        shape = ClickableSurfaceDefaults.shape(RoundedCornerShape(8.dp)),
        scale = ClickableSurfaceDefaults.scale(focusedScale = 1.02f),
        colors = ClickableSurfaceDefaults.colors(
            containerColor = if (highlighted) Color(0xFFB91C1C) else Color.White.copy(alpha = 0.07f),
            contentColor = Color.White,
            focusedContainerColor = if (destructive) Color(0xFFDC2626) else Color.White.copy(alpha = 0.16f),
            focusedContentColor = Color.White,
            disabledContainerColor = Color.White.copy(alpha = 0.03f),
            disabledContentColor = Color.White.copy(alpha = 0.2f)
        )
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 9.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                icon,
                contentDescription = null,
                tint = if (highlighted || !enabled) Color.White.copy(alpha = if (enabled) 1f else 0.25f) else accent,
                modifier = Modifier.size(13.dp)
            )
            Text(
                text,
                color = if (highlighted || !enabled) Color.White.copy(alpha = if (enabled) 1f else 0.25f) else accent,
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold
            )
        }
    }
}

@Composable
private fun SectionNote(text: String) {
    Text(
        text,
        color = Color.White.copy(alpha = 0.35f),
        fontSize = 12.sp,
        modifier = Modifier.padding(horizontal = 4.dp, vertical = 4.dp)
    )
}
