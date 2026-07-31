package net.footballia.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val FootballiaColors = darkColorScheme(
    primary = Color(0xFF22C55E),
    onPrimary = Color.Black,
    background = Color(0xFF0A0A0D),
    onBackground = Color.White,
    surface = Color(0xFF1A1A1F),
    onSurface = Color.White,
    surfaceVariant = Color(0xFF252530),
    outline = Color(0xFF2A2A35)
)

@Composable
fun FootballiaTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = FootballiaColors, content = content)
}
