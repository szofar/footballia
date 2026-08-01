package net.footballia.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Search
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.tv.material3.*
import net.footballia.data.Match
import net.footballia.viewmodel.FootballiaViewModel

private enum class NavSection(val label: String, val icon: ImageVector) {
    HOME("Home", Icons.Default.Home),
    COMPETITIONS("Competitions", Icons.Default.EmojiEvents),
    SEARCH("Search", Icons.Default.Search),
    CALENDAR("Calendar", Icons.Default.CalendarMonth)
}

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
fun MainScreen(viewModel: FootballiaViewModel) {
    var selectedSection by remember { mutableStateOf(NavSection.HOME) }
    var selectedMatch by remember { mutableStateOf<Match?>(null) }

    Box(modifier = Modifier.fillMaxSize().background(Color(0xFF0A0A0D))) {
        val match = selectedMatch
        if (match != null) {
            // Replaces the tab content entirely (rather than overlaying it) so the
            // match grid's D-pad focus doesn't linger underneath and steal input
            // from the player's controls.
            VideoPlayerScreen(match = match, onClose = { selectedMatch = null })
        } else {
            Column(modifier = Modifier.fillMaxSize()) {
                // Top tab row
                TabRow(
                    selectedTabIndex = selectedSection.ordinal,
                    modifier = Modifier.fillMaxWidth(),
                    indicator = { tabPositions, doesTabRowHaveFocus ->
                        tabPositions.getOrNull(selectedSection.ordinal)?.let { tabPosition ->
                            TabRowDefaults.PillIndicator(
                                currentTabPosition = tabPosition,
                                doesTabRowHaveFocus = doesTabRowHaveFocus
                            )
                        }
                    },
                    containerColor = Color(0xFF111116)
                ) {
                    NavSection.entries.forEach { section ->
                        Tab(
                            selected = selectedSection == section,
                            onFocus = { selectedSection = section },
                            onClick = { selectedSection = section }
                        ) {
                            Row(
                                horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(8.dp),
                                verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
                                modifier = Modifier.padding(horizontal = 20.dp, vertical = 14.dp)
                            ) {
                                androidx.compose.material3.Icon(
                                    imageVector = section.icon,
                                    contentDescription = null,
                                    tint = if (selectedSection == section) Color(0xFF22C55E) else Color.White.copy(alpha = 0.5f),
                                    modifier = Modifier.size(18.dp)
                                )
                                androidx.compose.material3.Text(
                                    text = section.label,
                                    color = if (selectedSection == section) Color.White else Color.White.copy(alpha = 0.5f),
                                    style = androidx.compose.material3.MaterialTheme.typography.labelLarge
                                )
                            }
                        }
                    }
                }

                // Content
                Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
                    when (selectedSection) {
                        NavSection.HOME         -> HomeScreen(viewModel) { selectedMatch = it }
                        NavSection.COMPETITIONS -> CompetitionsScreen(viewModel) { selectedMatch = it }
                        NavSection.SEARCH       -> SearchScreen(viewModel) { selectedMatch = it }
                        NavSection.CALENDAR     -> CalendarScreen(viewModel) { selectedMatch = it }
                    }
                }
            }
        }
    }
}

@Composable
fun RootScreen(viewModel: FootballiaViewModel) {
    when {
        viewModel.isCheckingSession -> Box(
            modifier = Modifier.fillMaxSize().background(Color(0xFF0A0A0D)),
            contentAlignment = androidx.compose.ui.Alignment.Center
        ) {
            androidx.compose.material3.CircularProgressIndicator(color = Color(0xFF22C55E))
        }
        viewModel.isLoggedIn -> MainScreen(viewModel)
        else -> LoginScreen(viewModel)
    }
}
