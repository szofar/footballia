package net.footballia.data

const val BASE_URL = "https://footballia.eu"

data class Match(
    val id: String,
    val slug: String,
    val homeTeam: String,
    val awayTeam: String,
    val competition: String,
    val stage: String,
    val date: String,
    val thumbnailHash: String,
    val homeTeamLogoPath: String,
    val awayTeamLogoPath: String
) {
    val thumbnailUrl: String? get() =
        if (thumbnailHash.isEmpty()) null else "$BASE_URL/cache/matches/$thumbnailHash.png"
    val homeTeamLogoUrl: String? get() =
        if (homeTeamLogoPath.isEmpty()) null else "$BASE_URL$homeTeamLogoPath"
    val awayTeamLogoUrl: String? get() =
        if (awayTeamLogoPath.isEmpty()) null else "$BASE_URL$awayTeamLogoPath"
    val matchPageUrl: String get() = "$BASE_URL/matches/$slug?locale=en"
    val title: String get() = "$homeTeam vs $awayTeam"
}

data class Team(
    val id: String,
    val slug: String,
    val name: String,
    val logoPath: String
) {
    val logoUrl: String? get() = if (logoPath.isEmpty()) null else "$BASE_URL$logoPath"
}

data class Competition(
    val id: String,
    val slug: String,
    val name: String,
    val logoPath: String
) {
    val logoUrl: String? get() = if (logoPath.isEmpty()) null else "$BASE_URL$logoPath"
}

/**
 * A run of competitions under one sub-heading of a catalogue category.
 *
 * The site's mega-menu nests two levels deep: a category (`<h5>Domestic</h5>`) holds either a
 * flat list of competitions or sub-headings — continents for the national-team columns, and
 * countries for Domestic, where each country also carries a CSS sprite class (`flag flag-es`)
 * that [countryCode] preserves. A category with no sub-headings is modelled as a single group
 * with an empty [name].
 */
data class CompetitionGroup(
    val id: String,
    val name: String,
    val countryCode: String = "",
    val competitions: List<Competition>
) {
    val flagEmoji: String? get() = countryFlagEmoji(countryCode)
}

data class CompetitionCategory(
    val id: String,
    val name: String,
    val groups: List<CompetitionGroup>
) {
    val competitions: List<Competition> get() = groups.flatMap { it.competitions }
}

/** Flag codes the site uses that aren't ISO 3166-1 alpha-2, mapped to their closest emoji. */
private val NON_ISO_FLAGS = mapOf(
    "england" to "\uD83C\uDFF4\uDB40\uDC67\uDB40\uDC62\uDB40\uDC65\uDB40\uDC6E\uDB40\uDC67\uDB40\uDC7F",
    "scotland" to "\uD83C\uDFF4\uDB40\uDC67\uDB40\uDC62\uDB40\uDC73\uDB40\uDC63\uDB40\uDC74\uDB40\uDC7F",
    "wales" to "\uD83C\uDFF4\uDB40\uDC67\uDB40\uDC62\uDB40\uDC77\uDB40\uDC6C\uDB40\uDC73\uDB40\uDC7F",
    // No dedicated emoji exists for either; fall back to the sovereign state's flag.
    "northern-ireland" to "\uD83C\uDDEC\uD83C\uDDE7",
    "kosovo" to "\uD83C\uDDFD\uD83C\uDDF0"
)

/**
 * Renders a footballia flag class suffix (`flag-es` → `es`) as a Unicode flag.
 *
 * The site only ships flags as a CSS sprite sheet, so there is no image URL to load; an ISO
 * alpha-2 code maps directly onto the two regional-indicator code points instead. Returns null
 * for anything unrecognised so callers can omit the icon rather than draw a tofu box.
 */
fun countryFlagEmoji(code: String): String? {
    val c = code.trim().lowercase()
    if (c.isEmpty()) return null
    NON_ISO_FLAGS[c]?.let { return it }
    if (c.length != 2 || c.any { it !in 'a'..'z' }) return null
    return buildString {
        c.forEach { ch -> appendCodePoint(0x1F1E6 + (ch - 'a')) }
    }
}

enum class SearchMode { PLAYERS, TEAMS }

data class SearchSuggestion(
    val id: String,
    val slug: String,
    val name: String,
    val mode: SearchMode
) {
    val urlPath: String get() = when (mode) {
        SearchMode.PLAYERS -> "/players/$slug"
        SearchMode.TEAMS   -> "/teams/$slug"
    }
}

/**
 * Note there is deliberately no "by date" filter: `/matches?date=…` is silently ignored by the
 * site and returns the unfiltered index. Calendar days are served from the year's event feed
 * instead — see [FootballiaRepository.loadCalendarYear].
 */
sealed class MatchFilter {
    object All : MatchFilter()
    data class ByTeam(val slug: String) : MatchFilter()
    data class ByPlayer(val slug: String) : MatchFilter()
    data class ByCompetition(val slug: String) : MatchFilter()

    val urlPath: String get() = when (this) {
        is All           -> "/matches"
        is ByTeam        -> "/teams/$slug"
        is ByPlayer      -> "/players/$slug"
        is ByCompetition -> "/competitions/$slug"
    }
}
