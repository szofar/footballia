package net.footballia.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Star
import androidx.compose.runtime.*
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.focusRestorer
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.*
import net.footballia.data.Match
import net.footballia.viewmodel.FootballiaViewModel

private enum class NavSection(val label: String, val icon: ImageVector) {
    CALENDAR("Calendar", Icons.Default.CalendarMonth),
    FAVORITES("Favorites", Icons.Default.Star),
    COMPETITIONS("Competitions", Icons.Default.EmojiEvents),
    SEARCH("Search", Icons.Default.Search),
    PROFILE("Profile", Icons.Default.Person)
}

// Master accounts get the Calendar first; everyone else gets Favorites first, with Calendar
// demoted to a locked placeholder (see CalendarLockedView below).
private fun navOrder(hasMasterAccess: Boolean): List<NavSection> = if (hasMasterAccess) {
    listOf(NavSection.CALENDAR, NavSection.FAVORITES, NavSection.COMPETITIONS, NavSection.SEARCH, NavSection.PROFILE)
} else {
    listOf(NavSection.FAVORITES, NavSection.COMPETITIONS, NavSection.CALENDAR, NavSection.SEARCH, NavSection.PROFILE)
}

@OptIn(ExperimentalTvMaterial3Api::class, ExperimentalComposeUiApi::class)
@Composable
fun MainScreen(viewModel: FootballiaViewModel) {
    val hasMasterAccess = viewModel.hasMasterAccess

    if (hasMasterAccess == null) {
        Box(modifier = Modifier.fillMaxSize().background(Color(0xFF0A0A0D)), contentAlignment = androidx.compose.ui.Alignment.Center) {
            androidx.compose.material3.CircularProgressIndicator(color = Color(0xFF22C55E))
        }
        return
    }

    val sections = remember(hasMasterAccess) { navOrder(hasMasterAccess) }
    var selectedSection by remember(hasMasterAccess) { mutableStateOf(sections.first()) }
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
                val selectedIndex = sections.indexOf(selectedSection)
                TabRow(
                    selectedTabIndex = selectedIndex,
                    // Without focusRestorer, any stray focus loss (e.g. when a screen swaps its
                    // content for a drill-down) falls back to the *first* tab, whose onFocus
                    // would then yank the user onto that tab. Restoring focus to the previously
                    // focused tab keeps the current section selected.
                    modifier = Modifier.fillMaxWidth().focusRestorer(),
                    indicator = { tabPositions, doesTabRowHaveFocus ->
                        tabPositions.getOrNull(selectedIndex)?.let { tabPosition ->
                            TabRowDefaults.PillIndicator(
                                currentTabPosition = tabPosition,
                                doesTabRowHaveFocus = doesTabRowHaveFocus
                            )
                        }
                    },
                    containerColor = Color(0xFF111116)
                ) {
                    sections.forEachIndexed { index, section ->
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
                        NavSection.CALENDAR ->
                            if (hasMasterAccess) CalendarScreen(viewModel) { selectedMatch = it }
                            else CalendarLockedView()
                        NavSection.FAVORITES     -> FavoritesScreen(viewModel) { selectedMatch = it }
                        NavSection.COMPETITIONS  -> CompetitionsScreen(viewModel) { selectedMatch = it }
                        NavSection.SEARCH        -> SearchScreen(viewModel) { selectedMatch = it }
                        NavSection.PROFILE       -> ProfileScreen(viewModel)
                    }
                }
            }
        }
    }
}

@Composable
private fun CalendarLockedView() {
    Box(modifier = Modifier.fillMaxSize(), contentAlignment = androidx.compose.ui.Alignment.Center) {
        Column(
            horizontalAlignment = androidx.compose.ui.Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            androidx.compose.material3.Icon(
                imageVector = Icons.Default.Lock,
                contentDescription = null,
                tint = Color.White.copy(alpha = 0.15f),
                modifier = Modifier.size(44.dp)
            )
            androidx.compose.material3.Text(
                "Calendar",
                color = Color.White.copy(alpha = 0.7f),
                fontSize = 22.sp,
                fontWeight = FontWeight.Bold
            )
            androidx.compose.material3.Text(
                "This is a Master feature.",
                color = Color.White.copy(alpha = 0.5f),
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold
            )
            androidx.compose.material3.Text(
                "Sign up for Master access on footballia.eu to browse matches by date — along with many more features.",
                color = Color.White.copy(alpha = 0.35f),
                fontSize = 13.sp,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                modifier = Modifier.widthIn(max = 460.dp)
            )
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
