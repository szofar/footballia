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
        modifier = Modifier.fillMaxWidth(),
        shape = CardDefaults.shape(shape = RoundedCornerShape(10.dp)),
        scale = CardDefaults.scale(focusedScale = 1.06f),
        colors = CardDefaults.colors(containerColor = Color(0xFF1A1A1F)),
        border = CardDefaults.border(
            focusedBorder = Border(BorderStroke(1.5.dp, Color(0xFF22C55E)), shape = RoundedCornerShape(10.dp)),
            border = Border(BorderStroke(0.dp, Color.Transparent), shape = RoundedCornerShape(10.dp))
        ),
        glow = CardDefaults.glow(focusedGlow = Glow(elevationColor = Color(0xFF22C55E).copy(alpha = 0.4f), elevation = 8.dp))
    ) {
        Column {
            // Thumbnail area: split crest view
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .aspectRatio(16f / 9f)
            ) {
                // Home team half
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxHeight()
                        .background(Color(0xFF1A1A21)),
                    contentAlignment = Alignment.Center
                ) {
                    TeamCrest(url = match.homeTeamLogoUrl, name = match.homeTeam)
                }

                // Divider
                Box(
                    modifier = Modifier
                        .width(1.dp)
                        .fillMaxHeight()
                        .background(Color.White.copy(alpha = 0.06f))
                )

                // Away team half
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxHeight()
                        .background(Color(0xFF1A1A21)),
                    contentAlignment = Alignment.Center
                ) {
                    TeamCrest(url = match.awayTeamLogoUrl, name = match.awayTeam)
                }
            }

            // Info area
            Column(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(3.dp)
            ) {
                // Team logos + title row
                Row(
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    TeamLogo(url = match.homeTeamLogoUrl)
                    TeamLogo(url = match.awayTeamLogoUrl)
                    Text(
                        text = match.title,
                        color = Color.White,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f)
                    )
                }

                // Competition + date
                val meta = listOf(match.competition, match.date).filter { it.isNotEmpty() }.joinToString("  ·  ")
                if (meta.isNotEmpty()) {
                    Text(
                        text = meta,
                        color = Color.White.copy(alpha = 0.4f),
                        fontSize = 10.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
        }
    }
}

@Composable
private fun TeamCrest(url: String?, name: String) {
    if (url != null) {
        AsyncImage(
            model = url,
            contentDescription = name,
            contentScale = ContentScale.Fit,
            modifier = Modifier.size(52.dp)
        )
    } else {
        Text(
            text = name.take(2).uppercase(),
            color = Color.White.copy(alpha = 0.25f),
            fontSize = 20.sp,
            fontWeight = FontWeight.Bold
        )
    }
}

@Composable
private fun TeamLogo(url: String?) {
    Box(
        modifier = Modifier
            .size(18.dp)
            .clip(RoundedCornerShape(3.dp))
            .background(Color.White.copy(alpha = 0.1f)),
        contentAlignment = Alignment.Center
    ) {
        if (url != null) {
            AsyncImage(model = url, contentDescription = null, contentScale = ContentScale.Fit, modifier = Modifier.size(16.dp))
        }
    }
}
