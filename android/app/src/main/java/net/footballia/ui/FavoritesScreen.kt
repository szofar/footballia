package net.footballia.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusProperties
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

@Composable
fun FavoritesScreen(viewModel: FootballiaViewModel, menuFocusRequester: FocusRequester, onMatchSelect: (Match) -> Unit) {
    LaunchedEffect(Unit) {
        if (viewModel.matches.isEmpty()) viewModel.loadMatches()
    }

    Column(modifier = Modifier.fillMaxSize()) {
        // Favorite teams cards
        if (viewModel.favoriteTeams.isNotEmpty()) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Color(0xFF111116))
                    .padding(vertical = 14.dp)
            ) {
                Text(
                    "Favorite Teams",
                    color = Color.White.copy(alpha = 0.4f),
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold,
                    letterSpacing = 1.sp,
                    modifier = Modifier.padding(horizontal = 28.dp, vertical = 4.dp)
                )
                LazyVerticalGrid(
                    columns = GridCells.Adaptive(minSize = 180.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                    contentPadding = PaddingValues(horizontal = 28.dp, vertical = 4.dp),
                    modifier = Modifier.fillMaxWidth().heightIn(max = 220.dp)
                ) {
                    items(viewModel.favoriteTeams, key = { it.id }) { team ->
                        FavoriteTeamCard(
                            team = team,
                            modifier = Modifier.focusProperties { up = menuFocusRequester }
                        ) {
                            viewModel.loadMatchesLastPage(MatchFilter.ByTeam(team.slug))
                        }
                    }
                }
            }
        }

        // Video grid fills remaining space
        VideoGridView(
            title = when (val f = viewModel.currentFilter) {
                is MatchFilter.All         -> "All Matches"
                is MatchFilter.ByTeam      -> f.slug.split("-").joinToString(" ") { it.replaceFirstChar { c -> c.uppercase() } }
                is MatchFilter.ByPlayer    -> f.slug.split("-").joinToString(" ") { it.replaceFirstChar { c -> c.uppercase() } }
                is MatchFilter.ByCompetition -> f.slug.split("-").joinToString(" ") { it.replaceFirstChar { c -> c.uppercase() } }
                is MatchFilter.ByDate      -> f.date
            },
            matches = viewModel.matches,
            isLoading = viewModel.isLoadingMatches,
            currentPage = viewModel.currentPage,
            hasNextPage = viewModel.hasNextPage,
            isReversed = viewModel.paginationReversed,
            onMatchSelect = onMatchSelect,
            onNextPage = {
                val next = if (viewModel.paginationReversed) viewModel.currentPage - 1 else viewModel.currentPage + 1
                viewModel.loadMatches(page = next)
            },
            onPreviousPage = {
                val prev = if (viewModel.paginationReversed) viewModel.currentPage + 1 else viewModel.currentPage - 1
                viewModel.loadMatches(page = prev)
            }
        )
    }
}

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
private fun FavoriteTeamCard(team: Team, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Surface(
        onClick = onClick,
        modifier = modifier.fillMaxWidth(),
        shape = ClickableSurfaceDefaults.shape(shape = RoundedCornerShape(10.dp)),
        scale = ClickableSurfaceDefaults.scale(focusedScale = 1.04f),
        colors = ClickableSurfaceDefaults.colors(
            containerColor = Color.White.copy(alpha = 0.05f),
            contentColor = Color.White,
            focusedContainerColor = Color.White.copy(alpha = 0.1f),
            focusedContentColor = Color.White
        ),
        border = ClickableSurfaceDefaults.border(
            focusedBorder = Border(androidx.compose.foundation.BorderStroke(1.dp, Color(0xFF22C55E).copy(alpha = 0.6f)), shape = RoundedCornerShape(10.dp))
        )
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier
                    .size(36.dp)
                    .background(Color.White.copy(alpha = 0.08f), RoundedCornerShape(6.dp)),
                contentAlignment = Alignment.Center
            ) {
                if (team.logoUrl != null) {
                    AsyncImage(model = team.logoUrl, contentDescription = null, contentScale = ContentScale.Fit, modifier = Modifier.size(28.dp))
                }
            }
            Text(team.name, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
        }
    }
}
