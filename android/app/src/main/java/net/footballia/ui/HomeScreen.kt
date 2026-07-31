package net.footballia.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import net.footballia.data.Match
import net.footballia.data.MatchFilter
import net.footballia.data.Team
import net.footballia.viewmodel.FootballiaViewModel

@Composable
fun HomeScreen(viewModel: FootballiaViewModel, onMatchSelect: (Match) -> Unit) {
    LaunchedEffect(Unit) {
        if (viewModel.matches.isEmpty()) viewModel.loadMatches()
    }

    Column(modifier = Modifier.fillMaxSize()) {
        // Featured teams strip
        if (viewModel.featuredTeams.isNotEmpty()) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Color(0xFF111116))
                    .padding(vertical = 14.dp)
            ) {
                Text(
                    "Featured Teams",
                    color = Color.White.copy(alpha = 0.4f),
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold,
                    letterSpacing = 1.sp,
                    modifier = Modifier.padding(horizontal = 28.dp, vertical = 4.dp)
                )
                Row(
                    modifier = Modifier
                        .horizontalScroll(rememberScrollState())
                        .padding(horizontal = 28.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    viewModel.featuredTeams.forEach { team ->
                        TeamChip(team = team) {
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

@Composable
private fun TeamChip(team: Team, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .clip(RoundedCornerShape(20.dp))
            .background(Color.White.copy(alpha = 0.07f))
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 7.dp),
        horizontalArrangement = Arrangement.spacedBy(7.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (team.logoUrl != null) {
            AsyncImage(
                model = team.logoUrl,
                contentDescription = team.name,
                contentScale = ContentScale.Fit,
                modifier = Modifier.size(18.dp)
            )
        }
        Text(team.name, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Medium)
    }
}
