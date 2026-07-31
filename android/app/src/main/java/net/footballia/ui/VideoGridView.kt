package net.footballia.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import net.footballia.data.Match

@Composable
fun VideoGridView(
    title: String,
    matches: List<Match>,
    isLoading: Boolean,
    currentPage: Int,
    hasNextPage: Boolean,
    isReversed: Boolean,
    onMatchSelect: (Match) -> Unit,
    onNextPage: () -> Unit,
    onPreviousPage: () -> Unit
) {
    val hasPreviousPage = currentPage > 1

    Column(modifier = Modifier.fillMaxSize().padding(horizontal = 28.dp)) {
        // Header row
        Row(
            modifier = Modifier.fillMaxWidth().padding(top = 28.dp, bottom = 16.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.Bottom
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(title, color = Color.White, fontSize = 24.sp, fontWeight = FontWeight.Bold)
                Text(
                    text = if (isLoading && matches.isEmpty()) "Loading matches…"
                           else "${matches.size} matches · page $currentPage",
                    color = Color.White.copy(alpha = 0.35f),
                    fontSize = 13.sp
                )
            }
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                PageButton(
                    icon = Icons.Default.ChevronLeft,
                    enabled = if (isReversed) hasNextPage else hasPreviousPage,
                    onClick = if (isReversed) onNextPage else onPreviousPage
                )
                PageButton(
                    icon = Icons.Default.ChevronRight,
                    enabled = if (isReversed) hasPreviousPage else hasNextPage,
                    onClick = if (isReversed) onPreviousPage else onNextPage
                )
            }
        }

        Box(modifier = Modifier.weight(1f)) {
            LazyVerticalGrid(
                columns = GridCells.Adaptive(minSize = 280.dp),
                horizontalArrangement = Arrangement.spacedBy(14.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
                contentPadding = PaddingValues(bottom = 28.dp),
                modifier = Modifier.fillMaxSize().alpha(if (isLoading) 0.35f else 1f)
            ) {
                items(matches, key = { it.id }) { match ->
                    VideoCardView(match = match, onClick = { onMatchSelect(match) })
                }
            }

            if (isLoading) {
                CircularProgressIndicator(
                    color = Color(0xFF22C55E),
                    modifier = Modifier.align(Alignment.Center)
                )
            }
        }
    }
}

@Composable
private fun PageButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    enabled: Boolean,
    onClick: () -> Unit
) {
    IconButton(
        onClick = onClick,
        enabled = enabled,
        modifier = Modifier
            .size(36.dp)
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = if (enabled) Color.White else Color.White.copy(alpha = 0.25f)
        )
    }
}
