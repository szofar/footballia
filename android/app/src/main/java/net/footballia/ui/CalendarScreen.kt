package net.footballia.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.*
import net.footballia.data.Match
import net.footballia.viewmodel.FootballiaViewModel
import java.text.DateFormatSymbols
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
fun CalendarScreen(viewModel: FootballiaViewModel, onMatchSelect: (Match) -> Unit) {
    LaunchedEffect(Unit) {
        val stale = viewModel.isStale("calendar")
        viewModel.startCalendar(force = stale)
        viewModel.markLoaded("calendar")
    }
    val selectedDay = viewModel.calendarSelectedDay

    Column(modifier = Modifier.fillMaxSize()) {
        // Header
        Column(
            modifier = Modifier.fillMaxWidth().background(Color(0xFF111116)).padding(horizontal = 28.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Column {
                    Text("Calendar", color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                    Text("Browse matches by date", color = Color.White.copy(alpha = 0.35f), fontSize = 13.sp)
                }
                if (viewModel.isLoadingCalendar) {
                    CircularProgressIndicator(modifier = Modifier.size(18.dp), color = Color(0xFF22C55E), strokeWidth = 2.dp)
                }
            }

            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                IconButton(onClick = { stepMonth(viewModel, -1) }) {
                    Icon(Icons.Default.ChevronLeft, null, tint = Color.White.copy(alpha = 0.6f))
                }
                Text(
                    text = "${monthName(viewModel.calendarMonth)} ${viewModel.calendarYear}",
                    color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.widthIn(min = 160.dp),
                )
                IconButton(onClick = { stepMonth(viewModel, 1) }) {
                    Icon(Icons.Default.ChevronRight, null, tint = Color.White.copy(alpha = 0.6f))
                }
            }
        }

        LazyVerticalGrid(
            columns = GridCells.Fixed(7),
            modifier = Modifier.fillMaxSize().padding(horizontal = 28.dp),
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
            contentPadding = PaddingValues(top = 16.dp, bottom = 28.dp)
        ) {
            // Day-of-week headers
            val headers = listOf("Mo", "Tu", "We", "Th", "Fr", "Sa", "Su")
            items(headers, key = { it }) { d ->
                Box(contentAlignment = Alignment.Center, modifier = Modifier.fillMaxWidth().height(32.dp)) {
                    Text(d, color = Color.White.copy(alpha = 0.3f), fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
                }
            }

            val days = computeDays(viewModel.calendarYear, viewModel.calendarMonth)
            itemsIndexed(days, key = { index, day -> if (day == null) "blank_$index" else "day_$day" }) { _, day ->
                if (day == null) {
                    Box(modifier = Modifier.fillMaxWidth().height(38.dp))
                } else {
                    val hasMatch = viewModel.calendarMatchDays.contains(day)
                    val isSelected = selectedDay == day
                    DayCell(
                        day = day,
                        hasMatch = hasMatch,
                        isSelected = isSelected,
                        onClick = { if (hasMatch) viewModel.selectCalendarDay(if (isSelected) null else day) }
                    )
                }
            }

            if (selectedDay != null) {
                val availableAfter = availableAfterDate(viewModel.calendarYear, viewModel.calendarMonth, selectedDay)
                item(span = { GridItemSpan(7) }) {
                    Column(modifier = Modifier.fillMaxWidth().padding(top = 20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                        Text(
                            "${monthName(viewModel.calendarMonth)} $selectedDay, ${viewModel.calendarYear}",
                            color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.SemiBold
                        )
                        if (availableAfter != null) {
                            TooRecentBanner(availableAfter = availableAfter)
                        } else if (viewModel.calendarMatches.isEmpty()) {
                            Text("No matches found for this date.", color = Color.White.copy(alpha = 0.35f), fontSize = 14.sp)
                        }
                    }
                }
                if (availableAfter == null) {
                    items(viewModel.calendarMatches, key = { "match_${it.id}" }, span = { GridItemSpan(2) }) { match ->
                        VideoCardView(match = match, onClick = { onMatchSelect(match) })
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
private fun DayCell(day: Int, hasMatch: Boolean, isSelected: Boolean, onClick: () -> Unit) {
    val containerColor = when {
        isSelected -> Color(0xFF22C55E)
        hasMatch   -> Color(0xFF22C55E).copy(alpha = 0.08f)
        else       -> Color.Transparent
    }
    val border = when {
        isSelected -> BorderStroke(0.dp, Color.Transparent)
        hasMatch   -> BorderStroke(1.dp, Color(0xFF22C55E).copy(alpha = 0.2f))
        else       -> BorderStroke(0.dp, Color.Transparent)
    }

    Surface(
        onClick = onClick,
        enabled = hasMatch,
        modifier = Modifier.fillMaxWidth().height(38.dp),
        shape = ClickableSurfaceDefaults.shape(RoundedCornerShape(8.dp)),
        colors = ClickableSurfaceDefaults.colors(
            containerColor = containerColor,
            contentColor = Color.White,
            disabledContainerColor = containerColor,
            disabledContentColor = Color.White,
            focusedContainerColor = if (hasMatch) Color(0xFF22C55E).copy(alpha = 0.18f) else containerColor,
            focusedContentColor = Color.White
        ),
        border = ClickableSurfaceDefaults.border(border = Border(border, shape = RoundedCornerShape(8.dp)))
    ) {
        Box(contentAlignment = Alignment.Center) {
            Text(
                text = "$day",
                fontSize = 13.sp,
                fontWeight = if (hasMatch) FontWeight.SemiBold else FontWeight.Normal,
                color = when {
                    isSelected -> Color.Black
                    hasMatch   -> Color(0xFF22C55E)
                    else       -> Color.White.copy(alpha = 0.25f)
                }
            )
        }
    }
}

private fun stepMonth(viewModel: FootballiaViewModel, delta: Int) {
    var m = viewModel.calendarMonth + delta
    var y = viewModel.calendarYear
    if (m < 1)  { m = 12; y -= 1 }
    if (m > 12) { m = 1;  y += 1 }
    viewModel.loadCalendar(y, m)
}

private fun monthName(month: Int): String =
    DateFormatSymbols(Locale.ENGLISH).months.getOrElse(month - 1) { "" }

private fun computeDays(year: Int, month: Int): List<Int?> {
    val cal = Calendar.getInstance().apply {
        set(Calendar.YEAR, year)
        set(Calendar.MONTH, month - 1)
        set(Calendar.DAY_OF_MONTH, 1)
    }
    val daysInMonth = cal.getActualMaximum(Calendar.DAY_OF_MONTH)
    val rawDow = cal.get(Calendar.DAY_OF_WEEK) // Sun=1, Mon=2 … Sat=7
    val offset = (rawDow + 5) % 7

    val days = mutableListOf<Int?>()
    repeat(offset) { days += null }
    (1..daysInMonth).forEach { days += it }
    while (days.size % 7 != 0) days += null
    return days
}

/** Returns the date on which the match becomes watchable (game date + 30 days) if the
 *  selected day is within the 30-day embargo window; null otherwise. */
private fun availableAfterDate(year: Int, month: Int, day: Int): java.util.Date? {
    val gameDay = Calendar.getInstance().apply {
        set(year, month - 1, day, 0, 0, 0)
        set(Calendar.MILLISECOND, 0)
    }
    val cutoff = Calendar.getInstance().apply {
        add(Calendar.DAY_OF_MONTH, -30)
        set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0);      set(Calendar.MILLISECOND, 0)
    }
    if (gameDay.before(cutoff)) return null
    return Calendar.getInstance().apply {
        timeInMillis = gameDay.timeInMillis
        add(Calendar.DAY_OF_MONTH, 30)
    }.time
}

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
private fun TooRecentBanner(availableAfter: java.util.Date) {
    val dateStr = SimpleDateFormat("MMMM d, yyyy", Locale.ENGLISH).format(availableAfter)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(Color.White.copy(alpha = 0.04f), RoundedCornerShape(10.dp))
            .padding(16.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = Icons.Default.ChevronRight,
            contentDescription = null,
            tint = Color.White.copy(alpha = 0.25f),
            modifier = Modifier.size(22.dp)
        )
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("Match not yet available", color = Color.White.copy(alpha = 0.6f), fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
            Text("This match will be available after $dateStr.", color = Color.White.copy(alpha = 0.35f), fontSize = 13.sp)
        }
    }
}
