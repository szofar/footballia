package net.footballia.data

import android.webkit.CookieManager as WebViewCookieManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.*
import org.json.JSONArray
import java.net.URLEncoder
import java.text.DateFormatSymbols
import java.util.Locale

class FootballiaRepository {

    companion object {
        private const val USER_AGENT =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
    }

    // Share cookies between OkHttp and WebView via Android's CookieManager.
    private val cookieJar = object : CookieJar {
        private val mgr = WebViewCookieManager.getInstance().apply { setAcceptCookie(true) }

        override fun saveFromResponse(url: HttpUrl, cookies: List<Cookie>) {
            val urlStr = url.toString()
            cookies.forEach { mgr.setCookie(urlStr, it.toString()) }
            mgr.flush()
        }

        override fun loadForRequest(url: HttpUrl): List<Cookie> {
            val raw = mgr.getCookie(url.toString()) ?: return emptyList()
            return raw.split(";").mapNotNull { pair ->
                val eq = pair.indexOf('=')
                if (eq < 0) return@mapNotNull null
                val name = pair.substring(0, eq).trim()
                val value = pair.substring(eq + 1).trim()
                runCatching {
                    Cookie.Builder().domain(url.host).name(name).value(value).build()
                }.getOrNull()
            }
        }
    }

    private val client = OkHttpClient.Builder()
        .cookieJar(cookieJar)
        .followRedirects(true)
        .build()

    fun clearCookies() {
        WebViewCookieManager.getInstance().removeAllCookies(null)
        WebViewCookieManager.getInstance().flush()
    }

    // MARK: - Auth

    suspend fun login(email: String, password: String): Boolean = withContext(Dispatchers.IO) {
        val signInUrl = "$BASE_URL/users/sign_in?locale=en"
        val pageHtml = fetchHtml(signInUrl)
        val csrf = extractCsrfToken(pageHtml)

        val form = FormBody.Builder()
            .add("utf8", "✓")
            .apply { if (csrf != null) add("authenticity_token", csrf) }
            .add("user[email]", email)
            .add("user[password]", password)
            .add("user[remember_me]", "1")
            .add("commit", "Sign in")
            .build()

        val request = Request.Builder()
            .url(signInUrl)
            .post(form)
            .header("User-Agent", USER_AGENT)
            .header("Origin", BASE_URL)
            .header("Referer", signInUrl)
            .build()

        val response = client.newCall(request).execute()
        !response.request.url.toString().contains("/users/sign_in")
    }

    /**
     * Checks whether a persisted cookie (e.g. the remember-me token) still authenticates us,
     * without needing the user's credentials. The "Sign in" nav link is only rendered for
     * unauthenticated users, so its absence means we have a live session.
     */
    suspend fun restoreSession(): Boolean = withContext(Dispatchers.IO) {
        val html = fetchHtml("$BASE_URL/?locale=en")
        html.isNotEmpty() && !html.contains("<span>Sign in</span>")
    }

    /**
     * The calendar page renders a "This is a Master feature" upsell banner in place of the
     * actual calendar for accounts without a Master subscription.
     */
    /**
     * Loads the calendar page once and infers Master entitlement from whether the site swapped
     * the calendar out for its upsell notice.
     *
     * Returns null when the page could not be loaded at all, so callers can tell "no Master
     * access" apart from "the check didn't run" — a network blip must not silently downgrade
     * the account and reshuffle the tab bar.
     */
    suspend fun checkMasterAccess(): Boolean? = withContext(Dispatchers.IO) {
        val html = runCatching { fetchHtml("$BASE_URL/calendar?locale=en") }.getOrNull()
        if (html.isNullOrEmpty()) null else !isMasterGated(html)
    }

    /**
     * Detects the Master paywall notice, e.g.
     * `<p class="alert alert-success">This is a Master feature. Access this and many more
     *  features! <a href="/master">Become a Master for as little as €3.99 p/m …</a></p>`
     *
     * Mirrors `FootballiaService.isMasterGated` in the Swift app. The fallback window is kept
     * narrow because Devise's own flash messages ("Signed in successfully.") reuse the same
     * `alert alert-success` class and would otherwise be read as a paywall.
     */
    fun isMasterGated(html: String): Boolean {
        val lower = html.lowercase()
        if (lower.contains("this is a master feature")) return true
        val alertIndex = lower.indexOf("alert alert-success")
        if (alertIndex < 0) return false
        val window = lower.substring(alertIndex, minOf(alertIndex + 600, lower.length))
        return window.contains("become a master")
    }

    // MARK: - HTML fetch

    suspend fun fetchHtml(url: String): String = withContext(Dispatchers.IO) {
        val req = Request.Builder()
            .url(url)
            .header("User-Agent", USER_AGENT)
            .header("Accept", "text/html,application/xhtml+xml")
            .build()
        client.newCall(req).execute().use { it.body?.string() ?: "" }
    }

    // MARK: - Matches

    suspend fun loadMatches(filter: MatchFilter = MatchFilter.All, page: Int = 1): Pair<List<Match>, Boolean> =
        withContext(Dispatchers.IO) {
            val url = "$BASE_URL${filter.urlPath}?locale=en&page=$page"
            val html = fetchHtml(url)
            Pair(parseMatchCards(html), html.contains("rel=\"next\""))
        }

    suspend fun loadMatchesLastPage(filter: MatchFilter): Triple<List<Match>, Int, Boolean> =
        withContext(Dispatchers.IO) {
            val page1Html = fetchHtml("$BASE_URL${filter.urlPath}?locale=en&page=1")
            val last = detectLastPage(page1Html)
            if (last <= 1) {
                return@withContext Triple(parseMatchCards(page1Html), 1, page1Html.contains("rel=\"next\""))
            }
            val lastHtml = fetchHtml("$BASE_URL${filter.urlPath}?locale=en&page=$last")
            Triple(parseMatchCards(lastHtml), last, lastHtml.contains("rel=\"next\""))
        }

    // MARK: - Featured teams

    suspend fun loadFeaturedTeams(): List<Team> = withContext(Dispatchers.IO) {
        parseTeams(fetchHtml("$BASE_URL/?locale=en"))
    }

    // MARK: - Team detail

    /**
     * Resolves a team's display name and crest from its own page so a team picked out of search
     * can be cached as a full favourite. Team search results only carry a name and a slug — the
     * crest lives on the team page, exposed as an Open Graph image.
     *
     * Never throws for a missing crest: a favourite with an empty [Team.logoPath] still renders
     * (the cards fall back to initials), so a markup change degrades instead of blocking the add.
     */
    suspend fun loadTeamDetails(slug: String, fallbackName: String = ""): Team =
        withContext(Dispatchers.IO) {
            val html = runCatching { fetchHtml("$BASE_URL/teams/$slug?locale=en") }.getOrDefault("")
            parseTeamDetail(html, slug, fallbackName)
        }

    // MARK: - Competitions

    suspend fun loadCompetitions(): List<CompetitionCategory> = withContext(Dispatchers.IO) {
        val cats = parseCompetitions(fetchHtml("$BASE_URL/competitions?locale=en"))
        if (cats.isNotEmpty()) return@withContext cats
        parseCompetitions(fetchHtml("$BASE_URL/?locale=en"))
    }

    // MARK: - Search

    suspend fun search(query: String, mode: SearchMode): List<SearchSuggestion> = withContext(Dispatchers.IO) {
        val encoded = URLEncoder.encode(query, "UTF-8")
        val (action, param) = when (mode) {
            SearchMode.PLAYERS -> Pair("/search_by_player", "player_name")
            SearchMode.TEAMS   -> Pair("/search_by_team", "team_name")
        }
        val html = fetchHtml("$BASE_URL$action?$param=$encoded&locale=en")
        when (mode) {
            SearchMode.PLAYERS -> parsePlayerSuggestions(html)
            SearchMode.TEAMS   -> parseTeamSuggestions(html)
        }
    }

    suspend fun loadMatchesForSuggestion(suggestion: SearchSuggestion): Triple<List<Match>, Int, Boolean> =
        withContext(Dispatchers.IO) {
            val page1Html = fetchHtml("$BASE_URL${suggestion.urlPath}?locale=en&page=1")
            val last = detectLastPage(page1Html)
            if (last <= 1) {
                return@withContext Triple(parseMatchCards(page1Html), 1, page1Html.contains("rel=\"next\""))
            }
            val lastHtml = fetchHtml("$BASE_URL${suggestion.urlPath}?locale=en&page=$last")
            Triple(parseMatchCards(lastHtml), last, lastHtml.contains("rel=\"next\""))
        }

    suspend fun loadSearchPage(page: Int, suggestion: SearchSuggestion): Pair<List<Match>, Boolean> =
        withContext(Dispatchers.IO) {
            val html = fetchHtml("$BASE_URL${suggestion.urlPath}?locale=en&page=$page")
            Pair(parseMatchCards(html), html.contains("rel=\"next\""))
        }

    // MARK: - Calendar

    /**
     * A year's worth of calendar matches, keyed by ISO `yyyy-MM-dd`.
     *
     * The calendar page is a FullCalendar widget: `/calendar/<year>` embeds every match of that
     * year in a JS `events: [...]` array. There is no per-day endpoint — `?date=` is ignored by
     * the server — so a single fetch per year backs both the highlighted days and the match list.
     */
    data class CalendarYear(
        val year: Int,
        val matchesByDate: Map<String, List<Match>> = emptyMap(),
        val isMasterGated: Boolean = false
    )

    suspend fun loadCalendarYear(year: Int): CalendarYear = withContext(Dispatchers.IO) {
        val html = runCatching { fetchHtml("$BASE_URL/calendar/$year?locale=en") }.getOrDefault("")
        if (html.isEmpty()) return@withContext CalendarYear(year)
        if (isMasterGated(html)) return@withContext CalendarYear(year, isMasterGated = true)
        CalendarYear(year, parseCalendarEvents(html, year))
    }

    // MARK: - HTML parsers

    private fun parseMatchCards(html: String): List<Match> {
        val results = mutableListOf<Match>()
        val seen = mutableSetOf<String>()

        for (part in html.split("href=\"/matches/").drop(1)) {
            val slug = part.takeWhile { it != '"' && it != '?' && it != '/' }
            if (slug.isEmpty() || slug in seen) continue
            seen += slug

            val window = part.take(4000)
            val hash = extractFirst("""/cache/matches/([a-f0-9]{32})\.png""", window) ?: continue
            val (home, away) = parseTeamNames(window, slug)
            val competition = extractFirst("""(?:competition|league|cup)[^>]*>\s*([^<]{2,60})""", window) ?: ""
            val date = extractFirst("""\b((?:19|20)\d{2})\b""", window) ?: ""
            val stage = extractFirst("""(?:stage|round|matchday|phase)[^>]*>\s*([^<]{2,40})""", window) ?: ""
            val (homeFlag, awayFlag) = extractFlagPaths(window)

            results += Match(
                id = slug, slug = slug,
                homeTeam = home, awayTeam = away,
                competition = competition.trim(), stage = stage.trim(), date = date.trim(),
                thumbnailHash = hash,
                homeTeamLogoPath = homeFlag, awayTeamLogoPath = awayFlag
            )
        }
        return results.ifEmpty { parseMatchTable(html) }
    }

    private fun parseMatchTable(html: String): List<Match> {
        val results = mutableListOf<Match>()
        val seen = mutableSetOf<String>()

        for (rowChunk in html.split("<tr").drop(1)) {
            val gt = rowChunk.indexOf('>').takeIf { it >= 0 } ?: continue
            val row = rowChunk.substring(gt + 1)
            if (!row.contains("href=\"/matches/")) continue

            val tds = row.split("<td").drop(1).mapNotNull { td ->
                val innerGt = td.indexOf('>').takeIf { it >= 0 } ?: return@mapNotNull null
                val end = td.indexOf("</td>").takeIf { it >= 0 } ?: return@mapNotNull null
                td.substring(innerGt + 1, end).replace(Regex("<[^>]+>"), " ").trim()
            }

            val idx = row.indexOf("href=\"/matches/").takeIf { it >= 0 } ?: continue
            val afterHref = row.substring(idx + "href=\"/matches/".length)
            val slug = afterHref.takeWhile { it != '"' && it != '?' && it != '/' }
            if (slug.isEmpty() || slug in seen) continue
            seen += slug

            val win = afterHref.take(600)
            val alts = win.split("alt=\"").drop(1).map { it.takeWhile { c -> c != '"' }.trim() }.filter { it.isNotEmpty() }
            val (homeFlag, awayFlag) = extractFlagPaths(win)

            results += Match(
                id = slug, slug = slug,
                homeTeam = alts.firstOrNull() ?: tds.getOrElse(1) { "" }.take(30),
                awayTeam = alts.getOrElse(1) { "" },
                competition = tds.getOrElse(2) { "" },
                stage = tds.getOrElse(3) { "" },
                date = tds.firstOrNull() ?: "",
                thumbnailHash = "",
                homeTeamLogoPath = homeFlag, awayTeamLogoPath = awayFlag
            )
        }
        return results.ifEmpty { parseMatchLinks(html) }
    }

    private fun parseMatchLinks(html: String): List<Match> {
        val results = mutableListOf<Match>()
        val seen = mutableSetOf<String>()

        for (part in html.split("href=\"/matches/").drop(1)) {
            val slug = part.takeWhile { it != '"' && it != '?' && it != '/' }
            if (slug.isEmpty() || slug in seen) continue
            seen += slug

            val window = part.take(800)
            val alts = window.split("alt=\"").drop(1).map { it.takeWhile { c -> c != '"' }.trim() }.filter { it.isNotEmpty() }
            var home = alts.firstOrNull() ?: ""
            var away = alts.getOrElse(1) { "" }

            if (home.isEmpty()) {
                val endAnchor = window.indexOf("</a>").takeIf { it >= 0 }
                if (endAnchor != null) {
                    val text = window.substring(0, endAnchor).replace(Regex("<[^>]+>"), " ").trim()
                    for (sep in listOf(" vs. ", " vs ", " - ", " – ")) {
                        val parts = text.split(sep)
                        if (parts.size >= 2) { home = parts[0].trim(); away = parts[1].trim(); break }
                    }
                }
            }
            if (home.isEmpty()) { val (h, a) = parseTeamNames(window, slug); home = h; away = a }

            val spans = window.split("<span").drop(1).mapNotNull { sp ->
                val g = sp.indexOf('>').takeIf { it >= 0 } ?: return@mapNotNull null
                val e = sp.indexOf("</span>").takeIf { it >= 0 } ?: return@mapNotNull null
                sp.substring(g + 1, e).trim().takeIf { it.isNotEmpty() && !it.contains('<') }
            }
            val (homeFlag, awayFlag) = extractFlagPaths(window)

            results += Match(
                id = slug, slug = slug,
                homeTeam = home, awayTeam = away,
                competition = spans.firstOrNull() ?: "",
                stage = "",
                date = spans.getOrElse(2) { spans.getOrElse(1) { "" } },
                thumbnailHash = "",
                homeTeamLogoPath = homeFlag, awayTeamLogoPath = awayFlag
            )
        }
        return results
    }

    private fun extractFlagPaths(html: String): Pair<String, String> {
        val paths = mutableListOf<String>()
        for (part in html.split("/uploads/team/").drop(1)) {
            val name = part.takeWhile { it != '"' && it != '\'' && it != ' ' && it != '?' }
            if (name.isNotEmpty()) paths += "/uploads/team/$name"
            if (paths.size >= 2) break
        }
        return Pair(paths.firstOrNull() ?: "", paths.getOrElse(1) { "" })
    }

    private fun parseTeamNames(html: String, slug: String): Pair<String, String> {
        for (pattern in listOf(
            """alt="([^"]+\s[-–]\s[^"]+)"""",
            """alt="([^"]+\svs\.?\s[^"]+)"""",
            """title="([^"]+\s[-–]\s[^"]+)""""
        )) {
            val combined = extractFirst(pattern, html) ?: continue
            for (sep in listOf(" - ", " – ", " vs ", " VS ")) {
                val parts = combined.split(sep)
                if (parts.size >= 2) return Pair(parts[0].trim(), parts.drop(1).joinToString(sep).trim())
            }
        }
        val words = slug.split("-").map { it.replaceFirstChar { c -> c.uppercase() } }
        val mid = words.size / 2
        return Pair(words.take(mid).joinToString(" "), words.drop(mid).joinToString(" "))
    }

    private fun parseTeams(html: String): List<Team> {
        val results = mutableListOf<Team>()
        val seen = mutableSetOf<String>()
        for (part in html.split("href=\"/teams/").drop(1)) {
            val slug = part.takeWhile { it != '"' && it != '?' && it != '/' }
            if (slug.isEmpty() || slug in seen) continue
            seen += slug
            val window = part.take(600)
            val rawName = extractFirst("""title="([^"]+)"""", window)
                ?: extractFirst("""alt="([^"]+)"""", window)
                ?: slugToName(slug)
            val name = cleanTeamName(rawName)
            val logoPath = extractFirst("""src="(/uploads/team/[^"]+)"""", window) ?: ""
            if (name.isNotEmpty()) results += Team(id = slug, slug = slug, name = name, logoPath = logoPath)
        }
        return results
    }

    /**
     * Pulls a team's name and crest out of its page's Open Graph tags, e.g.
     *   <meta content="https://footballia.eu/uploads/team/logo/16/medium_….png" property="og:image" />
     *   <meta content="Real Madrid full matches" property="og:title" />
     *
     * Attribute order is matched both ways round because the site emits content-first, but that
     * is a templating detail rather than a guarantee.
     */
    private fun parseTeamDetail(html: String, slug: String, fallbackName: String): Team {
        // Scope to <head>, where the og tags live, so a stray content=/property= pair in the
        // body can't win. Falls back to a generous prefix if the closing tag ever goes missing.
        val headEnd = html.indexOf("</head>", ignoreCase = true)
        val head = if (headEnd > 0) html.substring(0, headEnd) else html.take(60000)

        val ogImage = extractFirst("""property="og:image"[^>]*content="([^"]+)"""", head)
            ?: extractFirst("""content="([^"]+)"[^>]*property="og:image"""", head)
        val logoPath = ogImage
            ?.removePrefix(BASE_URL)
            ?.takeIf { it.startsWith("/uploads/team/") }
            ?: ""

        val ogTitle = extractFirst("""property="og:title"[^>]*content="([^"]+)"""", head)
            ?: extractFirst("""content="([^"]+)"[^>]*property="og:title"""", head)
        val name = ogTitle?.let { cleanTeamName(it) }?.takeIf { it.isNotEmpty() }
            ?: fallbackName.trim().takeIf { it.isNotEmpty() }
            ?: slugToName(slug)

        return Team(id = slug, slug = slug, name = name, logoPath = logoPath)
    }

    private fun slugToName(slug: String): String =
        slug.split("-").joinToString(" ") { it.replaceFirstChar { c -> c.uppercase() } }

    private fun cleanTeamName(raw: String): String =
        raw.replace(" full matches", "").replace(" matches", "").trim()

    /**
     * Parses the competitions mega-menu, which nests two levels deep:
     *
     * ```
     * <div class="col-md-3"><h5>Domestic</h5><ul class="links">
     *   <li>Europe</li>
     *   <ul class="ul-toggle … sub-menu">
     *     <li data-keep-open="true"><a title="England"><span class="flag flag-england"></span>England</a>
     *       <ul class="links" style="display:none;"><li><a href="/competitions/fa-cup" …>FA Cup</a></li>…</ul>
     * ```
     *
     * The Domestic column groups by country (each with a flag sprite class); the national-team
     * columns group by continent with plain `<li>Europe</li>` headings; "Others" is a flat list
     * and becomes a single unnamed group.
     *
     * Each column is bounded at its closing `</ul></div>` rather than a fixed character budget —
     * Domestic alone carries ~280 competitions and was previously truncated mid-list.
     */
    private fun parseCompetitions(html: String): List<CompetitionCategory> {
        val categories = mutableListOf<CompetitionCategory>()
        val seenSlugs = mutableSetOf<String>()

        for (chunk in html.split("<div class=\"col-md-3\">").drop(1)) {
            if (!chunk.contains("href=\"/competitions/")) continue
            val end = chunk.indexOf("</ul></div>").takeIf { it >= 0 } ?: chunk.length
            val column = chunk.substring(0, end)
            val categoryName = (extractFirst("<h[4-6][^>]*>\\s*([^<]+)\\s*</h[4-6]>", column) ?: "Other").trim()

            val groups = parseCompetitionGroups(column, categoryName, seenSlugs)
            if (groups.isNotEmpty()) {
                categories += CompetitionCategory(id = categoryName, name = categoryName, groups = groups)
            }
        }
        return categories
    }

    /**
     * Splits one catalogue column into its sub-headings.
     *
     * Headings are matched in document order so competitions attach to the heading that precedes
     * them; anything before the first heading becomes an unnamed leading group, which is how a
     * flat column ("Others") ends up as a single group.
     */
    private fun parseCompetitionGroups(
        column: String,
        categoryName: String,
        seenSlugs: MutableSet<String>
    ): List<CompetitionGroup> {
        // A continent heading (`<li>Europe</li>`) or a country row (`<a title="England"><span
        // class="flag flag-england" …>`). Country rows carry the sprite class; continents don't.
        val heading = Regex(
            """<li>([^<>]{2,40})</li>|<a title="([^"]+)"><span class="flag flag-([a-z\-]+)""",
            RegexOption.IGNORE_CASE
        )
        val boundaries = heading.findAll(column).map { m ->
            val name = (m.groupValues[1].ifEmpty { m.groupValues[2] }).trim()
            Triple(m.range.first, name, m.groupValues[3])
        }.filter { it.second.isNotEmpty() }.toList()

        val groups = mutableListOf<CompetitionGroup>()
        val starts = listOf(0) + boundaries.map { it.first }
        for (i in starts.indices) {
            val from = starts[i]
            val to = starts.getOrNull(i + 1) ?: column.length
            val name = if (i == 0) "" else boundaries[i - 1].second
            val code = if (i == 0) "" else boundaries[i - 1].third
            val comps = parseCompetitionLinks(column.substring(from, to), seenSlugs)
            if (comps.isEmpty()) continue
            groups += CompetitionGroup(
                id = "$categoryName/${name.ifEmpty { "all" }}",
                name = name,
                countryCode = code,
                competitions = comps
            )
        }
        return groups
    }

    private fun parseCompetitionLinks(section: String, seenSlugs: MutableSet<String>): List<Competition> {
        val comps = mutableListOf<Competition>()
        for (part in section.split("href=\"/competitions/").drop(1)) {
            val slug = part.takeWhile { it != '"' && it != '?' && it != '/' }
            if (slug.isEmpty() || slug in seenSlugs) continue
            seenSlugs += slug
            val name = (extractFirst("""title="([^"]+)"""", part.take(200))
                ?: extractFirst(">([^<]{2,60})<", part.take(100))
                ?: slugToName(slug)).trim()
            comps += Competition(id = slug, slug = slug, name = decodeEntities(name), logoPath = "")
        }
        return comps
    }

    /** Minimal entity decoding — competition names carry `&#39;` and `&amp;` (e.g. "Full Members' Cup"). */
    private fun decodeEntities(text: String): String =
        text.replace("&#39;", "'").replace("&quot;", "\"")
            .replace("&lt;", "<").replace("&gt;", ">")
            .replace("&nbsp;", " ").replace("&amp;", "&")

    private fun parsePlayerSuggestions(html: String): List<SearchSuggestion> {
        val results = mutableListOf<SearchSuggestion>()
        val seen = mutableSetOf<String>()
        for (row in html.split("<tr>").drop(1)) {
            if (!row.contains("href=\"/players/")) continue
            val idx = row.indexOf("href=\"/players/").takeIf { it >= 0 } ?: continue
            val slug = row.substring(idx + "href=\"/players/".length).takeWhile { it != '"' && it != '?' && it != '/' }
            if (slug.isEmpty() || slug in seen) continue
            seen += slug

            val tds = row.split("<td>").drop(1)
            val fullName = if (tds.size >= 2) {
                val end = tds[1].indexOf("</td>").takeIf { it >= 0 }
                if (end != null) tds[1].substring(0, end).replace(Regex("<[^>]+>"), "").trim() else ""
            } else ""

            val name = fullName.ifEmpty {
                slug.split("-").joinToString(" ") { it.replaceFirstChar { c -> c.uppercase() } }
            }
            results += SearchSuggestion(id = slug, slug = slug, name = name, mode = SearchMode.PLAYERS)
        }
        return results
    }

    private fun parseTeamSuggestions(html: String): List<SearchSuggestion> {
        val results = mutableListOf<SearchSuggestion>()
        val seen = mutableSetOf<String>()
        val area = html.substringAfter("found for ", html)

        for (part in area.split("href=\"/teams/").drop(1)) {
            val slug = part.takeWhile { it != '"' && it != '?' && it != '/' }
            if (slug.isEmpty() || slug in seen) continue
            seen += slug

            val window = part.take(200)
            val gt = window.indexOf('>').takeIf { it >= 0 }
            val end = window.indexOf("</a>").takeIf { it >= 0 }
            val name = if (gt != null && end != null && gt < end)
                window.substring(gt + 1, end).replace(Regex("<[^>]+>"), "").trim()
            else
                slug.split("-").joinToString(" ") { it.replaceFirstChar { c -> c.uppercase() } }

            results += SearchSuggestion(id = slug, slug = slug, name = name, mode = SearchMode.TEAMS)
            if (results.size >= 30) break
        }
        return results
    }

    /**
     * Pulls the FullCalendar `events: [...]` array out of the calendar page's inline script.
     *
     * Each entry looks like
     * `{"competition":"Serie A","start":"2026-01-03","url":"/matches/…","home_team":"<span
     *  class='logo'><img alt=\"…\" src=\"/uploads/team/…\"/></span>Name","away_team":"…"}`
     * — the team fields are HTML fragments, so the crest comes from their `src` and the display
     * name from the text after the closing `</span>`.
     */
    private fun parseCalendarEvents(html: String, year: Int): Map<String, List<Match>> {
        val json = extractEventsArray(html) ?: return emptyMap()
        val array = runCatching { JSONArray(json) }.getOrNull() ?: return emptyMap()
        val byDate = linkedMapOf<String, MutableList<Match>>()
        val seenPerDate = mutableMapOf<String, MutableSet<String>>()

        for (i in 0 until array.length()) {
            val event = array.optJSONObject(i) ?: continue
            val date = event.optString("start")
            // The feed occasionally carries neighbouring years' fixtures; keep the page's own.
            if (date.length != 10 || date.take(4).toIntOrNull() != year) continue

            val url = event.optString("url")
            val slug = url.substringAfter("/matches/", "").takeWhile { it != '?' && it != '/' }
            if (slug.isEmpty()) continue
            if (!seenPerDate.getOrPut(date) { mutableSetOf() }.add(slug)) continue

            val (homeName, homeLogo) = parseCalendarTeam(event.optString("home_team"))
            val (awayName, awayLogo) = parseCalendarTeam(event.optString("away_team"))

            byDate.getOrPut(date) { mutableListOf() } += Match(
                id = slug, slug = slug,
                homeTeam = homeName, awayTeam = awayName,
                competition = event.optString("competition").trim(),
                stage = "",
                date = formatCalendarDate(date),
                thumbnailHash = "",
                homeTeamLogoPath = homeLogo, awayTeamLogoPath = awayLogo
            )
        }
        return byDate
    }

    /**
     * Extracts the balanced `[...]` literal following `events:` in the page's setup script.
     *
     * Candidates are filtered twice because third-party scripts on the page declare similar
     * keys: an identifier that merely *ends* in "events" (New Relic's `generic_events:`) is
     * skipped, as is any `events:` not followed by an array literal.
     */
    private fun extractEventsArray(html: String): String? {
        var search = 0
        while (true) {
            val marker = html.indexOf("events:", search).takeIf { it >= 0 } ?: return null
            search = marker + 1

            val before = html.getOrNull(marker - 1)
            if (before != null && (before.isLetterOrDigit() || before == '_' || before == '.')) continue

            var start = marker + "events:".length
            while (start < html.length && html[start].isWhitespace()) start++
            if (start >= html.length || html[start] != '[') continue

            extractBalancedArray(html, start)?.let { return it }
        }
    }

    private fun extractBalancedArray(html: String, start: Int): String? {
        var depth = 0
        var inString = false
        var escaped = false
        for (i in start until html.length) {
            val c = html[i]
            if (inString) {
                when {
                    escaped -> escaped = false
                    c == '\\' -> escaped = true
                    c == '"' -> inString = false
                }
                continue
            }
            when (c) {
                '"' -> inString = true
                '[' -> depth++
                ']' -> { depth--; if (depth == 0) return html.substring(start, i + 1) }
            }
        }
        return null
    }

    /** Splits a calendar `home_team`/`away_team` HTML fragment into (display name, crest path). */
    private fun parseCalendarTeam(fragment: String): Pair<String, String> {
        if (fragment.isEmpty()) return Pair("", "")
        val logo = extractFirst("""src="(/uploads/team/[^"]+)"""", fragment) ?: ""
        val name = fragment.substringAfterLast("</span>", fragment)
            .replace(Regex("<[^>]+>"), "")
            .trim()
            .ifEmpty { extractFirst("""alt="([^"]+)"""", fragment) ?: "" }
        return Pair(name, logo)
    }

    /** `2026-01-03` → `January 3, 2026`, matching the date style used by the table layouts. */
    private fun formatCalendarDate(iso: String): String {
        val parts = iso.split("-")
        if (parts.size != 3) return iso
        val month = DateFormatSymbols(Locale.ENGLISH).months.getOrNull((parts[1].toIntOrNull() ?: 0) - 1)
            ?: return iso
        val day = parts[2].toIntOrNull() ?: return iso
        return "$month $day, ${parts[0]}"
    }

    /**
     * Highest page number linked from the pagination strip.
     *
     * Scanning is scoped to the `<ul class="pagination">` block because page numbers also appear
     * in the page's language-switcher links, which always point at page 1. Three separators are
     * needed: competition pages link `?page=N`, while player/team pages carry an existing query
     * parameter and link `&amp;page=N` — HTML-escaped, so a bare `&page=` never matches.
     */
    private fun detectLastPage(html: String): Int {
        val start = html.indexOf("class=\"pagination")
        val scope = if (start >= 0) {
            val end = html.indexOf("</ul>", start).takeIf { it >= 0 } ?: html.length
            html.substring(start, end)
        } else html

        var max = 1
        for (sep in listOf("?page=", "&page=", "&amp;page=")) {
            for (part in scope.split(sep).drop(1)) {
                val n = part.takeWhile { it.isDigit() }.toIntOrNull() ?: continue
                if (n > max) max = n
            }
        }
        return max
    }

    private fun extractCsrfToken(html: String): String? =
        extractFirst("""name="authenticity_token"[^>]*value="([^"]+)"""", html)
            ?: extractFirst("""value="([^"]+)"[^>]*name="authenticity_token"""", html)
            ?: extractFirst("""<meta name="csrf-token" content="([^"]+)"""", html)

    private fun extractFirst(pattern: String, text: String): String? = runCatching {
        Regex(pattern, RegexOption.IGNORE_CASE).find(text)?.groupValues?.getOrNull(1)
    }.getOrNull()
}
