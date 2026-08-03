package net.footballia.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.*
import coil.compose.AsyncImage
import net.footballia.data.CalendarSectionData
import net.footballia.data.Match
import net.footballia.data.MatchFilter
import net.footballia.data.Team
import net.footballia.viewmodel.FootballiaViewModel
import java.text.SimpleDateFormat
import java.util.Locale

/**
 * The Favorites page: a grid of team cards followed by a rolling two-week match feed.
 * Mirrors FavoritesView.swift.
 */
@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
fun FavoritesScreen(viewModel: FootballiaViewModel, onMatchSelect: (Match) -> Unit) {
    LaunchedEffect(Unit) { viewModel.startCalendarList() }

    var selectedTeam by remember { mutableStateOf<Team?>(null) }

    val team = selectedTeam
    if (team != null) {
        val backFocusRequester = remember { FocusRequester() }
        LaunchedEffect(team.slug) { runCatching { backFocusRequester.requestFocus() } }

        Column(modifier = Modifier.fillMaxSize()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Color(0xFF111116))
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                IconButton(
                    onClick = { selectedTeam = null },
                    modifier = Modifier.focusRequester(backFocusRequester)
                ) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = Color.White.copy(alpha = 0.6f))
                }
                Text(team.name, color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
                if (viewModel.isLoadingMatches) {
                    Spacer(Modifier.weight(1f))
                    CircularProgressIndicator(modifier = Modifier.size(18.dp), color = Color(0xFF22C55E), strokeWidth = 2.dp)
                }
            }
            VideoGridView(
                title = team.name,
                matches = viewModel.matches,
                isLoading = viewModel.isLoadingMatches,
                currentPage = viewModel.currentPage,
                hasNextPage = viewModel.hasNextPage,
                isReversed = viewModel.paginationReversed,
                onMatchSelect = onMatchSelect,
                onNextPage = { viewModel.loadMatches(MatchFilter.ByTeam(team.slug), viewModel.currentPage + 1) },
                onPreviousPage = { viewModel.loadMatches(MatchFilter.ByTeam(team.slug), viewModel.currentPage - 1) }
            )
        }
        return
    }

    val sections = viewModel.calendarListSections
    val showCalendar = sections.isNotEmpty() || viewModel.isLoadingMoreCalendar

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(bottom = 28.dp)
    ) {
        // Page header
        item(key = "header") {
            Column(
                modifier = Modifier.padding(start = 28.dp, end = 28.dp, top = 30.dp, bottom = 24.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Text("Favorites", color = Color.White, fontSize = 24.sp, fontWeight = FontWeight.Bold)
                Text(
                    if (viewModel.favoriteTeams.isEmpty()) "Your teams will appear here"
                    else "${viewModel.favoriteTeams.size} teams",
                    color = Color.White.copy(alpha = 0.35f),
                    fontSize = 13.sp
                )
            }
        }

        // Team cards — rendered in chunked rows so the LazyColumn owns all scrolling
        if (viewModel.favoriteTeams.isEmpty()) {
            item(key = "empty_teams") {
                Box(
                    modifier = Modifier.fillMaxWidth().height(160.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        if (viewModel.favoritesLoaded) {
                            Text("No favorite teams", color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                            Text("Add teams from Profile › Favorite Teams.", color = Color.White.copy(alpha = 0.3f), fontSize = 13.sp)
                        } else {
                            CircularProgressIndicator(color = Color(0xFF22C55E))
                            Text("Loading teams…", color = Color.White.copy(alpha = 0.3f), fontSize = 13.sp)
                        }
                    }
                }
            }
        } else {
            val teams = viewModel.favoriteTeams
            // 4 columns; remainder row gets spacer-filled gaps
            val cols = 4
            teams.chunked(cols).forEachIndexed { rowIdx, row ->
                item(key = "team_row_$rowIdx") {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 28.dp)
                            .padding(bottom = 12.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        row.forEach { t ->
                            Box(modifier = Modifier.weight(1f)) {
                                FavoriteTeamCard(team = t) {
                                    selectedTeam = t
                                    viewModel.loadMatchesLastPage(MatchFilter.ByTeam(t.slug))
                                }
                            }
                        }
                        repeat(cols - row.size) { Spacer(Modifier.weight(1f)) }
                    }
                }
            }
        }

        // Calendar match feed
        if (showCalendar) {
            // Divider + section header
            item(key = "cal_header") {
                Column {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 28.dp)
                            .padding(top = 32.dp)
                            .height(1.dp)
                            .background(Color.White.copy(alpha = 0.06f))
                    )
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 28.dp)
                            .padding(top = 20.dp, bottom = 16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text("Recent Matches", color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                        if (viewModel.isLoadingMoreCalendar) {
                            CircularProgressIndicator(modifier = Modifier.size(18.dp), color = Color(0xFF22C55E), strokeWidth = 2.dp)
                        }
                    }
                }
            }

            // Date section rows
            itemsIndexed(sections, key = { _, s -> "cal_${s.date}" }) { index, section ->
                CalendarDateRow(
                    section = section,
                    isLast = index == sections.lastIndex,
                    isLoadingMore = viewModel.isLoadingMoreCalendar,
                    onMatchSelect = onMatchSelect,
                    onLoadMore = { viewModel.loadMoreCalendarList() }
                )
            }

            // Favorites toggle
            item(key = "cal_toggle") {
                FavoritesOnlyToggle(
                    checked = viewModel.calendarShowFavoritesOnly,
                    onCheckedChange = { viewModel.setCalendarFavoritesOnly(it) },
                    modifier = Modifier.padding(horizontal = 28.dp, vertical = 16.dp)
                )
            }
        }
    }
}

// MARK: - Calendar date row

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
private fun CalendarDateRow(
    section: CalendarSectionData,
    isLast: Boolean,
    isLoadingMore: Boolean,
    onMatchSelect: (Match) -> Unit,
    onLoadMore: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 16.dp, bottom = 4.dp)
    ) {
        Text(
            text = formatSectionDate(section.date),
            color = Color.White.copy(alpha = 0.55f),
            fontSize = 14.sp,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(start = 28.dp, end = 28.dp, bottom = 12.dp)
        )

        LazyRow(
            contentPadding = PaddingValues(horizontal = 28.dp),
            horizontalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            items(section.matches, key = { it.id }) { match ->
                Box(modifier = Modifier.width(260.dp)) {
                    VideoCardView(match = match, onClick = { onMatchSelect(match) })
                }
            }

            if (isLast) {
                item(key = "load_more") {
                    CalendarLoadMoreCard(isLoading = isLoadingMore, onLoadMore = onLoadMore)
                }
            }
        }
    }
}

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
private fun CalendarLoadMoreCard(isLoading: Boolean, onLoadMore: () -> Unit) {
    var hasFocused by remember { mutableStateOf(false) }

    Surface(
        onClick = { if (!isLoading) onLoadMore() },
        modifier = Modifier
            .width(100.dp)
            .height(146.dp)
            .onFocusChanged { state ->
                if (state.isFocused && !hasFocused) {
                    hasFocused = true
                    if (!isLoading) onLoadMore()
                }
                if (!state.isFocused) hasFocused = false
            },
        shape = ClickableSurfaceDefaults.shape(RoundedCornerShape(10.dp)),
        colors = ClickableSurfaceDefaults.colors(
            containerColor = Color.White.copy(alpha = 0.05f),
            focusedContainerColor = Color.White.copy(alpha = 0.10f)
        )
    ) {
        Box(contentAlignment = Alignment.Center, modifier = Modifier.fillMaxSize()) {
            if (isLoading) {
                CircularProgressIndicator(
                    modifier = Modifier.size(24.dp),
                    color = Color(0xFF22C55E),
                    strokeWidth = 2.dp
                )
            } else {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text("»", color = Color(0xFF22C55E), fontSize = 22.sp, fontWeight = FontWeight.Bold)
                    Text(
                        text = "More\nweeks",
                        color = Color.White.copy(alpha = 0.45f),
                        fontSize = 12.sp,
                        textAlign = TextAlign.Center
                    )
                }
            }
        }
    }
}

@Composable
private fun FavoritesOnlyToggle(
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .background(Color.White.copy(alpha = 0.04f), RoundedCornerShape(10.dp))
            .padding(horizontal = 20.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text("Show only favorite teams", color = Color.White.copy(alpha = 0.6f), fontSize = 14.sp)
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            colors = SwitchDefaults.colors(
                checkedThumbColor = Color.White,
                checkedTrackColor = Color(0xFF22C55E),
                uncheckedThumbColor = Color.White.copy(alpha = 0.6f),
                uncheckedTrackColor = Color.White.copy(alpha = 0.15f)
            )
        )
    }
}

// MARK: - Team card

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
private fun FavoriteTeamCard(team: Team, onClick: () -> Unit) {
    Surface(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        shape = ClickableSurfaceDefaults.shape(shape = RoundedCornerShape(10.dp)),
        scale = ClickableSurfaceDefaults.scale(focusedScale = 1.04f),
        colors = ClickableSurfaceDefaults.colors(
            containerColor = Color.White.copy(alpha = 0.05f),
            contentColor = Color.White,
            focusedContainerColor = Color.White.copy(alpha = 0.1f),
            focusedContentColor = Color.White
        ),
        border = ClickableSurfaceDefaults.border(
            focusedBorder = Border(
                BorderStroke(1.dp, Color(0xFF22C55E).copy(alpha = 0.6f)),
                shape = RoundedCornerShape(10.dp)
            )
        )
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 18.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(56.dp)
                    .background(Color.White.copy(alpha = 0.08f), RoundedCornerShape(8.dp)),
                contentAlignment = Alignment.Center
            ) {
                if (team.logoUrl != null) {
                    AsyncImage(
                        model = team.logoUrl,
                        contentDescription = null,
                        contentScale = ContentScale.Fit,
                        modifier = Modifier.size(44.dp)
                    )
                } else {
                    Text(
                        team.name.take(2).uppercase(),
                        color = Color.White.copy(alpha = 0.4f),
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
            }
            Text(
                team.name,
                color = Color.White,
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 2,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth()
            )
        }
    }
}

private fun formatSectionDate(isoDate: String): String =
    try {
        val date = SimpleDateFormat("yyyy-MM-dd", Locale.ENGLISH).parse(isoDate) ?: return isoDate
        SimpleDateFormat("EEEE, MMMM d", Locale.ENGLISH).format(date)
    } catch (e: Exception) { isoDate }
