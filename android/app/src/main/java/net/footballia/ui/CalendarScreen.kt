package net.footballia.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.*
import net.footballia.data.CalendarSectionData
import net.footballia.data.Match
import net.footballia.viewmodel.FootballiaViewModel
import java.text.SimpleDateFormat
import java.util.Locale

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
fun CalendarScreen(viewModel: FootballiaViewModel, onMatchSelect: (Match) -> Unit) {
    LaunchedEffect(Unit) { viewModel.startCalendarList() }

    val sections = viewModel.calendarListSections
    val isLoading = viewModel.isLoadingMoreCalendar
    val showFavoritesOnly = viewModel.calendarShowFavoritesOnly

    Column(modifier = Modifier.fillMaxSize()) {
        // Header
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(Color(0xFF111116))
                .padding(horizontal = 28.dp, vertical = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Column {
                Text("Calendar", color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                Text("Browse matches by date", color = Color.White.copy(alpha = 0.35f), fontSize = 13.sp)
            }
            if (isLoading) {
                CircularProgressIndicator(
                    modifier = Modifier.size(18.dp),
                    color = Color(0xFF22C55E),
                    strokeWidth = 2.dp
                )
            }
        }

        if (sections.isEmpty() && !isLoading) {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = Color(0xFF22C55E))
            }
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(bottom = 28.dp)
            ) {
                itemsIndexed(sections, key = { _, s -> s.date }) { index, section ->
                    val isLast = index == sections.lastIndex
                    DateSectionRow(
                        section = section,
                        isLast = isLast,
                        isLoadingMore = isLoading,
                        onMatchSelect = onMatchSelect,
                        onLoadMore = { viewModel.loadMoreCalendarList() }
                    )
                }

                // Favorites toggle
                item(key = "favorites_toggle") {
                    FavoritesToggleRow(
                        checked = showFavoritesOnly,
                        onCheckedChange = { viewModel.setCalendarFavoritesOnly(it) },
                        modifier = Modifier.padding(horizontal = 28.dp, vertical = 20.dp)
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
private fun DateSectionRow(
    section: CalendarSectionData,
    isLast: Boolean,
    isLoadingMore: Boolean,
    onMatchSelect: (Match) -> Unit,
    onLoadMore: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 20.dp, bottom = 8.dp)
    ) {
        Text(
            text = formatSectionDate(section.date),
            color = Color.White.copy(alpha = 0.6f),
            fontSize = 15.sp,
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

            // "Load more" card at the right end of the last section
            if (isLast) {
                item(key = "load_more") {
                    LoadMoreCard(isLoading = isLoadingMore, onLoadMore = onLoadMore)
                }
            }
        }
    }
}

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
private fun LoadMoreCard(isLoading: Boolean, onLoadMore: () -> Unit) {
    var hasFocused by remember { mutableStateOf(false) }

    Surface(
        onClick = { if (!isLoading) onLoadMore() },
        modifier = Modifier
            .width(100.dp)
            .height(146.dp) // matches ~260dp card at 16:9 aspect = 146dp height for thumb
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
private fun FavoritesToggleRow(
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
        Text(
            text = "Show only favorite teams",
            color = Color.White.copy(alpha = 0.6f),
            fontSize = 14.sp
        )
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

private fun formatSectionDate(isoDate: String): String {
    return try {
        val parser = SimpleDateFormat("yyyy-MM-dd", Locale.ENGLISH)
        val date = parser.parse(isoDate) ?: return isoDate
        val formatter = SimpleDateFormat("EEEE, MMMM d", Locale.ENGLISH)
        formatter.format(date)
    } catch (e: Exception) {
        isoDate
    }
}
