package net.footballia.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.*
import coil.compose.AsyncImage
import net.footballia.data.Match
import net.footballia.data.MatchFilter
import net.footballia.data.Team
import net.footballia.viewmodel.FootballiaViewModel

/**
 * The Favorites page: a grid of cards for the cached top-teams list. Selecting a team drills
 * into that team's matches, most recent first. Mirrors FavoritesView.swift.
 */
@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
fun FavoritesScreen(viewModel: FootballiaViewModel, onMatchSelect: (Match) -> Unit) {
    var selectedTeam by remember { mutableStateOf<Team?>(null) }

    val team = selectedTeam
    if (team != null) {
        // Pull focus into the drill-down as soon as it opens; otherwise focus is left orphaned
        // by the content swap and bounces back up to the tab row.
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
                    Icon(Icons.Default.ArrowBack, contentDescription = "Back", tint = Color.White.copy(alpha = 0.6f))
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
                onNextPage = {
                    viewModel.loadMatches(MatchFilter.ByTeam(team.slug), viewModel.currentPage + 1)
                },
                onPreviousPage = {
                    viewModel.loadMatches(MatchFilter.ByTeam(team.slug), viewModel.currentPage - 1)
                }
            )
        }
        return
    }

    if (viewModel.favoriteTeams.isEmpty()) {
        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                if (viewModel.favoritesLoaded) {
                    Text("No favorite teams", color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                    Text(
                        "Add teams from Profile › Favorite Teams.",
                        color = Color.White.copy(alpha = 0.3f),
                        fontSize = 13.sp
                    )
                } else {
                    CircularProgressIndicator(color = Color(0xFF22C55E))
                    Text("Loading teams…", color = Color.White.copy(alpha = 0.3f), fontSize = 13.sp)
                }
            }
        }
        return
    }

    LazyVerticalGrid(
        columns = GridCells.Adaptive(minSize = 180.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        contentPadding = PaddingValues(28.dp),
        modifier = Modifier.fillMaxSize()
    ) {
        item(span = { GridItemSpan(maxLineSpan) }) {
            Column(
                verticalArrangement = Arrangement.spacedBy(4.dp),
                modifier = Modifier.padding(bottom = 8.dp)
            ) {
                Text("Favorites", color = Color.White, fontSize = 24.sp, fontWeight = FontWeight.Bold)
                Text(
                    "${viewModel.favoriteTeams.size} teams",
                    color = Color.White.copy(alpha = 0.35f),
                    fontSize = 13.sp
                )
            }
        }

        items(viewModel.favoriteTeams, key = { "team_${it.id}" }) { favorite ->
            FavoriteTeamCard(team = favorite) {
                selectedTeam = favorite
                viewModel.loadMatchesLastPage(MatchFilter.ByTeam(favorite.slug))
            }
        }
    }
}

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
                maxLines = 2
            )
        }
    }
}
