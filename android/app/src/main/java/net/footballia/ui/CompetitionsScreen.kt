package net.footballia.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material3.CircularProgressIndicator
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
import net.footballia.data.Competition
import net.footballia.data.Match
import net.footballia.data.MatchFilter
import net.footballia.viewmodel.FootballiaViewModel

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
fun CompetitionsScreen(viewModel: FootballiaViewModel, onMatchSelect: (Match) -> Unit) {
    var selectedCompetition by remember { mutableStateOf<Competition?>(null) }

    LaunchedEffect(Unit) { viewModel.loadCompetitions() }

    if (selectedCompetition != null) {
        val comp = selectedCompetition!!
        // Pull focus into the drill-down as soon as it opens; otherwise focus is left orphaned
        // by the content swap and bounces back up to the tab row.
        val backFocusRequester = remember { FocusRequester() }
        LaunchedEffect(comp.slug) { runCatching { backFocusRequester.requestFocus() } }

        Column(modifier = Modifier.fillMaxSize()) {
            // Back bar
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Color(0xFF111116))
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                IconButton(
                    onClick = { selectedCompetition = null },
                    modifier = Modifier.focusRequester(backFocusRequester)
                ) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = Color.White.copy(alpha = 0.6f))
                }
                Text(comp.name, color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
                if (viewModel.isLoadingMatches) {
                    Spacer(Modifier.weight(1f))
                    CircularProgressIndicator(modifier = Modifier.size(18.dp), color = Color(0xFF22C55E), strokeWidth = 2.dp)
                }
            }

            VideoGridView(
                title = comp.name,
                matches = viewModel.matches,
                isLoading = viewModel.isLoadingMatches,
                currentPage = viewModel.currentPage,
                hasNextPage = viewModel.hasNextPage,
                isReversed = viewModel.paginationReversed,
                onMatchSelect = onMatchSelect,
                onNextPage = {
                    viewModel.loadMatches(MatchFilter.ByCompetition(comp.slug), viewModel.currentPage + 1)
                },
                onPreviousPage = {
                    viewModel.loadMatches(MatchFilter.ByCompetition(comp.slug), viewModel.currentPage - 1)
                }
            )
        }
    } else {
        // Catalogue
        if (viewModel.isLoadingCompetitions) {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = Color(0xFF22C55E))
            }
        } else {
            LazyVerticalGrid(
                columns = GridCells.Adaptive(minSize = 180.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
                contentPadding = PaddingValues(28.dp),
                modifier = Modifier.fillMaxSize()
            ) {
                viewModel.competitionCategories.forEach { category ->
                    item(span = { androidx.compose.foundation.lazy.grid.GridItemSpan(maxLineSpan) }) {
                        Text(
                            category.name.uppercase(),
                            color = Color.White.copy(alpha = 0.4f),
                            fontSize = 11.sp,
                            fontWeight = FontWeight.SemiBold,
                            letterSpacing = 1.5.sp,
                            modifier = Modifier.padding(top = 12.dp)
                        )
                    }
                    category.groups.forEach { group ->
                        // Country/continent sub-heading; flat categories have one unnamed group.
                        if (group.name.isNotEmpty()) {
                            item(
                                key = "group_${group.id}",
                                span = { androidx.compose.foundation.lazy.grid.GridItemSpan(maxLineSpan) }
                            ) {
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                                    modifier = Modifier.padding(top = 4.dp)
                                ) {
                                    group.flagEmoji?.let { flag ->
                                        Text(flag, fontSize = 15.sp)
                                    }
                                    Text(
                                        group.name,
                                        color = Color.White.copy(alpha = 0.75f),
                                        fontSize = 14.sp,
                                        fontWeight = FontWeight.SemiBold
                                    )
                                }
                            }
                        }
                        items(group.competitions, key = { it.id }) { comp ->
                            CompetitionCard(competition = comp, onClick = {
                                selectedCompetition = comp
                                viewModel.loadMatchesLastPage(MatchFilter.ByCompetition(comp.slug))
                            })
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
private fun CompetitionCard(competition: Competition, onClick: () -> Unit) {
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
            focusedBorder = Border(BorderStroke(1.dp, Color(0xFF22C55E).copy(alpha = 0.6f)), shape = RoundedCornerShape(10.dp))
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
                if (competition.logoUrl != null) {
                    AsyncImage(model = competition.logoUrl, contentDescription = null, contentScale = ContentScale.Fit, modifier = Modifier.size(28.dp))
                } else {
                    Icon(Icons.Default.EmojiEvents, contentDescription = null, tint = Color.White.copy(alpha = 0.2f), modifier = Modifier.size(18.dp))
                }
            }
            Text(competition.name, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
        }
    }
}
