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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Border
import androidx.tv.material3.ClickableSurfaceDefaults
import androidx.tv.material3.ExperimentalTvMaterial3Api
import androidx.tv.material3.Icon
import androidx.tv.material3.Surface
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
    // The left/right arrows always mean "lower page number" / "higher page number" —
    // which callback performs that depends on isReversed, but whether it's currently
    // possible does not (hasPreviousPage/hasNextPage already reflect the loaded page).
    val canGoBack = hasPreviousPage
    val canGoForward = hasNextPage
    val onBack = if (isReversed) onNextPage else onPreviousPage
    val onForward = if (isReversed) onPreviousPage else onNextPage

    Column(modifier = Modifier.fillMaxSize().padding(horizontal = 28.dp)) {
        // Header row
        Column(
            modifier = Modifier.fillMaxWidth().padding(top = 28.dp, bottom = 16.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Text(title, color = Color.White, fontSize = 24.sp, fontWeight = FontWeight.Bold)
            Text(
                text = if (isLoading && matches.isEmpty()) "Loading matches…" else "${matches.size} matches",
                color = Color.White.copy(alpha = 0.35f),
                fontSize = 13.sp
            )
        }

        Row(modifier = Modifier.weight(1f).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            PageArrow(icon = Icons.Default.ChevronLeft, enabled = canGoBack, onClick = onBack)

            Box(modifier = Modifier.weight(1f).fillMaxHeight()) {
                LazyVerticalGrid(
                    columns = GridCells.Adaptive(minSize = 280.dp),
                    horizontalArrangement = Arrangement.spacedBy(14.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp),
                    contentPadding = PaddingValues(bottom = 28.dp),
                    modifier = Modifier.fillMaxSize().alpha(if (isLoading) 0.35f else 1f)
                ) {
                    // The site lists matches oldest-first; the last row is the most recent,
                    // so reverse for display to put the most recent match top-left.
                    items(matches.asReversed(), key = { it.id }) { match ->
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

            PageArrow(icon = Icons.Default.ChevronRight, enabled = canGoForward, onClick = onForward)
        }
    }
}

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
private fun PageArrow(
    icon: ImageVector,
    enabled: Boolean,
    onClick: () -> Unit
) {
    Surface(
        onClick = onClick,
        enabled = enabled,
        modifier = Modifier
            .padding(horizontal = 4.dp)
            .width(40.dp)
            .fillMaxHeight(0.45f),
        shape = ClickableSurfaceDefaults.shape(shape = androidx.compose.foundation.shape.RoundedCornerShape(20.dp)),
        colors = ClickableSurfaceDefaults.colors(
            containerColor = Color.White.copy(alpha = 0.05f),
            contentColor = Color.White,
            focusedContainerColor = Color(0xFF22C55E).copy(alpha = 0.3f),
            focusedContentColor = Color.White,
            disabledContainerColor = Color.Transparent,
            disabledContentColor = Color.White.copy(alpha = 0.12f)
        ),
        border = ClickableSurfaceDefaults.border(
            focusedBorder = Border(
                androidx.compose.foundation.BorderStroke(1.5.dp, Color(0xFF22C55E)),
                shape = androidx.compose.foundation.shape.RoundedCornerShape(20.dp)
            )
        )
    ) {
        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = if (enabled) Color.White else Color.White.copy(alpha = 0.15f)
            )
        }
    }
}
