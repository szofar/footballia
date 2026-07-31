package net.footballia.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.*
import coil.compose.AsyncImage
import net.footballia.data.Match

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
fun VideoCardView(match: Match, onClick: () -> Unit) {
    Card(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth().aspectRatio(16f / 9f),
        shape = CardDefaults.shape(shape = RoundedCornerShape(10.dp)),
        scale = CardDefaults.scale(focusedScale = 1.06f),
        colors = CardDefaults.colors(containerColor = Color(0xFF1A1A1F)),
        border = CardDefaults.border(
            focusedBorder = Border(BorderStroke(1.5.dp, Color(0xFF22C55E)), shape = RoundedCornerShape(10.dp)),
            border = Border(BorderStroke(0.dp, Color.Transparent), shape = RoundedCornerShape(10.dp))
        ),
        glow = CardDefaults.glow(focusedGlow = Glow(elevationColor = Color(0xFF22C55E).copy(alpha = 0.4f), elevation = 8.dp))
    ) {
        Box(modifier = Modifier.fillMaxSize()) {
            // Thumbnail
            if (match.thumbnailUrl != null) {
                AsyncImage(
                    model = match.thumbnailUrl,
                    contentDescription = match.title,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize()
                )
            } else {
                Box(modifier = Modifier.fillMaxSize().background(Color(0xFF252530)))
            }

            // Gradient overlay
            Box(
                modifier = Modifier.fillMaxSize().background(
                    Brush.verticalGradient(
                        0f to Color.Transparent,
                        0.5f to Color.Black.copy(alpha = 0.3f),
                        1f to Color.Black.copy(alpha = 0.85f)
                    )
                )
            )

            // Team logos + info
            Column(
                modifier = Modifier.fillMaxWidth().align(Alignment.BottomCenter).padding(10.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                // Team logos row
                Row(
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    TeamLogo(url = match.homeTeamLogoUrl)
                    TeamLogo(url = match.awayTeamLogoUrl)
                }

                // Match title
                Text(
                    text = match.title,
                    color = Color.White,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )

                // Competition + date
                val meta = listOf(match.competition, match.date).filter { it.isNotEmpty() }.joinToString("  ·  ")
                if (meta.isNotEmpty()) {
                    Text(text = meta, color = Color.White.copy(alpha = 0.5f), fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
}

@Composable
private fun TeamLogo(url: String?) {
    Box(
        modifier = Modifier
            .size(22.dp)
            .clip(RoundedCornerShape(3.dp))
            .background(Color.White.copy(alpha = 0.1f)),
        contentAlignment = Alignment.Center
    ) {
        if (url != null) {
            AsyncImage(model = url, contentDescription = null, contentScale = ContentScale.Fit, modifier = Modifier.size(20.dp))
        }
    }
}
