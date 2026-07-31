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

data class CompetitionCategory(
    val id: String,
    val name: String,
    val competitions: List<Competition>
)

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

sealed class MatchFilter {
    object All : MatchFilter()
    data class ByTeam(val slug: String) : MatchFilter()
    data class ByPlayer(val slug: String) : MatchFilter()
    data class ByCompetition(val slug: String) : MatchFilter()
    data class ByDate(val date: String) : MatchFilter()

    val urlPath: String get() = when (this) {
        is All           -> "/matches"
        is ByTeam        -> "/teams/$slug"
        is ByPlayer      -> "/players/$slug"
        is ByCompetition -> "/competitions/$slug"
        is ByDate        -> "/matches"
    }

    val extraQuery: String get() = if (this is ByDate) "&date=$date" else ""
}
