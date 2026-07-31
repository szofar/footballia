package net.footballia.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.*
import net.footballia.data.Match
import net.footballia.data.SearchMode
import net.footballia.data.SearchSuggestion
import net.footballia.viewmodel.FootballiaViewModel

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
fun SearchScreen(viewModel: FootballiaViewModel, onMatchSelect: (Match) -> Unit) {
    var query by remember { mutableStateOf("") }
    var mode by remember { mutableStateOf(SearchMode.PLAYERS) }

    LaunchedEffect(query, mode) {
        val q = query.trim()
        viewModel.clearActiveSuggestion()
        if (q.isEmpty()) { viewModel.clearSearch(); return@LaunchedEffect }
        kotlinx.coroutines.delay(300)
        viewModel.search(q, mode)
    }

    val activeSuggestion = viewModel.activeSuggestion

    Column(modifier = Modifier.fillMaxSize()) {
        // Search bar
        Column(
            modifier = Modifier.fillMaxWidth().background(Color(0xFF111116)).padding(horizontal = 28.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                // Mode toggle
                Row(
                    modifier = Modifier.background(Color.White.copy(alpha = 0.07f), RoundedCornerShape(10.dp)).padding(3.dp),
                    horizontalArrangement = Arrangement.spacedBy(0.dp)
                ) {
                    SearchMode.entries.forEach { m ->
                        val selected = mode == m
                        Surface(
                            onClick = { mode = m; viewModel.clearSearch() },
                            shape = ClickableSurfaceDefaults.shape(RoundedCornerShape(7.dp)),
                            colors = ClickableSurfaceDefaults.colors(
                                containerColor = if (selected) Color(0xFF22C55E) else Color.Transparent,
                                contentColor = Color.White,
                                focusedContainerColor = if (selected) Color(0xFF22C55E) else Color.White.copy(alpha = 0.1f),
                                focusedContentColor = Color.White
                            )
                        ) {
                            Row(
                                modifier = Modifier.padding(horizontal = 14.dp, vertical = 7.dp),
                                horizontalArrangement = Arrangement.spacedBy(6.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Icon(
                                    imageVector = if (m == SearchMode.PLAYERS) Icons.Default.Person else Icons.Default.Shield,
                                    contentDescription = null,
                                    tint = if (selected) Color.Black else Color.White.copy(alpha = 0.5f),
                                    modifier = Modifier.size(14.dp)
                                )
                                androidx.compose.material3.Text(
                                    text = if (m == SearchMode.PLAYERS) "Players" else "Teams",
                                    color = if (selected) Color.Black else Color.White.copy(alpha = 0.5f),
                                    fontSize = 13.sp, fontWeight = FontWeight.Medium
                                )
                            }
                        }
                    }
                }

                // Text field
                BasicTextField(
                    value = query,
                    onValueChange = { query = it },
                    singleLine = true,
                    textStyle = TextStyle(color = Color.White, fontSize = 14.sp),
                    cursorBrush = SolidColor(Color(0xFF22C55E)),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                    keyboardActions = KeyboardActions(onSearch = { viewModel.search(query.trim(), mode) }),
                    decorationBox = { inner ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .background(Color.White.copy(alpha = 0.07f), RoundedCornerShape(10.dp))
                                .padding(horizontal = 12.dp, vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            if (viewModel.isSearching) {
                                CircularProgressIndicator(modifier = Modifier.size(16.dp), color = Color(0xFF22C55E), strokeWidth = 2.dp)
                            } else {
                                Icon(Icons.Default.Search, contentDescription = null, tint = Color.White.copy(alpha = 0.4f), modifier = Modifier.size(16.dp))
                            }
                            Box(modifier = Modifier.weight(1f)) {
                                if (query.isEmpty()) androidx.compose.material3.Text(
                                    if (mode == SearchMode.PLAYERS) "Search players…" else "Search teams…",
                                    color = Color.White.copy(alpha = 0.3f), fontSize = 14.sp
                                )
                                inner()
                            }
                            if (query.isNotEmpty()) {
                                IconButton(onClick = { query = ""; viewModel.clearSearch() }, modifier = Modifier.size(20.dp)) {
                                    Icon(Icons.Default.Clear, contentDescription = "Clear", tint = Color.White.copy(alpha = 0.4f))
                                }
                            }
                        }
                    },
                    modifier = Modifier.weight(1f)
                )
            }
        }

        // Content
        if (activeSuggestion != null) {
            Column(modifier = Modifier.fillMaxSize()) {
                // Back bar
                Row(
                    modifier = Modifier.fillMaxWidth().background(Color(0xFF0F0F14)).padding(horizontal = 16.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    IconButton(onClick = { viewModel.clearActiveSuggestion() }) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back", tint = Color.White.copy(alpha = 0.6f))
                    }
                    androidx.compose.material3.Text(activeSuggestion.name, color = Color.White, fontWeight = FontWeight.SemiBold)
                }

                if (viewModel.isLoadingSearchMatches && viewModel.searchResults.isEmpty()) {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = Color(0xFF22C55E))
                    }
                } else {
                    VideoGridView(
                        title = activeSuggestion.name,
                        matches = viewModel.searchResults,
                        isLoading = viewModel.isLoadingSearchMatches,
                        currentPage = viewModel.searchCurrentPage,
                        hasNextPage = viewModel.searchHasNextPage,
                        isReversed = viewModel.searchPaginationReversed,
                        onMatchSelect = onMatchSelect,
                        onNextPage = {
                            val next = if (viewModel.searchPaginationReversed) viewModel.searchCurrentPage - 1 else viewModel.searchCurrentPage + 1
                            viewModel.loadSearchPage(next)
                        },
                        onPreviousPage = {
                            val prev = if (viewModel.searchPaginationReversed) viewModel.searchCurrentPage + 1 else viewModel.searchCurrentPage - 1
                            viewModel.loadSearchPage(prev)
                        }
                    )
                }
            }
        } else {
            when {
                query.isBlank() -> EmptyPrompt(Icons.Default.Search, "Search for a ${if (mode == SearchMode.PLAYERS) "player" else "team"} name.")
                viewModel.isSearching -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = Color(0xFF22C55E)) }
                viewModel.searchError != null -> EmptyPrompt(Icons.Default.Search, viewModel.searchError!!)
                viewModel.searchSuggestions.isEmpty() -> EmptyPrompt(Icons.Default.Search, "No results.")
                else -> {
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(horizontal = 28.dp, vertical = 20.dp),
                        verticalArrangement = Arrangement.spacedBy(2.dp)
                    ) {
                        item {
                            androidx.compose.material3.Text(
                                "${viewModel.searchSuggestions.size} results",
                                color = Color.White.copy(alpha = 0.4f), fontSize = 12.sp, fontWeight = FontWeight.SemiBold,
                                modifier = Modifier.padding(bottom = 10.dp)
                            )
                        }
                        items(viewModel.searchSuggestions, key = { it.id }) { suggestion ->
                            SuggestionRow(suggestion = suggestion) {
                                viewModel.loadMatchesForSuggestion(suggestion)
                            }
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
private fun SuggestionRow(suggestion: SearchSuggestion, onClick: () -> Unit) {
    Surface(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        shape = ClickableSurfaceDefaults.shape(RoundedCornerShape(8.dp)),
        colors = ClickableSurfaceDefaults.colors(
            containerColor = Color.Transparent,
            contentColor = Color.White,
            focusedContainerColor = Color.White.copy(alpha = 0.07f),
            focusedContentColor = Color.White
        )
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = if (suggestion.mode == SearchMode.PLAYERS) Icons.Default.Person else Icons.Default.Shield,
                contentDescription = null,
                tint = Color(0xFF22C55E).copy(alpha = 0.7f),
                modifier = Modifier.size(16.dp)
            )
            androidx.compose.material3.Text(suggestion.name, color = Color.White, fontSize = 14.sp, modifier = Modifier.weight(1f))
        }
    }
}

@Composable
private fun EmptyPrompt(icon: androidx.compose.ui.graphics.vector.ImageVector, text: String) {
    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Icon(icon, contentDescription = null, tint = Color.White.copy(alpha = 0.1f), modifier = Modifier.size(48.dp))
            androidx.compose.material3.Text(text, color = Color.White.copy(alpha = 0.35f), fontSize = 14.sp)
        }
    }
}
