import Foundation
import Observation

/// A group of matches that all took place on the same date, used by the calendar list view.
struct CalendarSection: Identifiable {
    let date: String    // ISO "yyyy-MM-dd"
    let matches: [Match]
    var id: String { date }
}

@MainActor
@Observable
final class FootballiaService {

    // MARK: - Auth state
    var isLoggedIn        = false
    var isCheckingSession = false
    var isLoading         = false
    var loginError: String?

    // MARK: - Match browsing state
    var matches: [Match] = []
    var isLoadingMatches = false
    var currentPage  = 1
    var hasNextPage  = false
    var currentFilter: MatchFilter = .all
    var paginationReversed = false

    // MARK: - Master access
    /// `true` when the account can use Master-only features (the Calendar).
    /// Determined by loading the calendar page once at login / session restore, and cached so
    /// the tab order is stable at launch instead of waiting on (and flip-flopping with) the
    /// network check.
    var hasMasterAccess = UserDefaults.standard.bool(forKey: FootballiaService.masterAccessKey)
    var didCheckMasterAccess = false

    static let masterAccessKey = "footballia.hasMasterAccess"

    // MARK: - Favourite teams
    /// The cached "top teams" list, seeded from the site's featured-teams strip on
    /// first launch and persisted from then on. The Profile tab edits this list and the
    /// Favorites page renders it, so both stay in sync through this single property.
    var favoriteTeams: [Team] = FavoriteTeamsStore.load()

    /// The live featured-teams strip from the homepage (used only to seed the cache).
    var featuredTeams: [Team] = []

    /// Favourite-team editing state for the Profile tab. Deliberately separate from the
    /// Search tab's state so editing favourites never disturbs an in-progress search there.
    var favoriteTeamSearchResults: [SearchSuggestion] = []
    var isSearchingFavoriteTeams = false
    var favoriteTeamSearchError: String?

    /// Slugs whose crest/name lookup is still in flight, so rows can show a spinner.
    var pendingFavoriteSlugs: Set<String> = []

    // MARK: - Account
    var accountEmail: String? = UserDefaults.standard.string(forKey: "footballia.accountEmail")

    // MARK: - Competitions catalogue
    var competitionCategories: [CompetitionCategory] = []
    var isLoadingCompetitions = false

    // MARK: - Search
    var searchSuggestions: [SearchSuggestion] = []
    var searchResults: [Match] = []
    var isSearching           = false
    var isLoadingSearchMatches = false
    var searchError: String?  = nil
    var searchCurrentPage     = 1
    var searchHasNextPage     = false
    var searchTotalPages      = 1
    var searchPaginationReversed = true

    // MARK: - Calendar (legacy month-grid state — kept for Master-access check wiring)
    var calendarYear  = Calendar.current.component(.year,  from: Date())
    var calendarMonth = Calendar.current.component(.month, from: Date())
    var isLoadingCalendar = false

    /// One entry per fetched year, keyed by ISO `yyyy-MM-dd`. `/calendar/<year>` returns the
    /// whole year in one payload, so a year is fetched at most once per session.
    private var calendarCache: [Int: [String: [Match]]] = [:]
    private var calendarStarted = false

    // MARK: - Calendar list view

    /// Unfiltered sections in descending date order (newest first), built from `calendarCache`.
    private var calendarListRawSections: [CalendarSection] = []
    /// The next "load more" call fetches the 14-day window ending just before this date.
    private var calendarListNextFetchEnd: Date = Date()
    private var calendarListLoaded = false

    var calendarShowFavoritesOnly = false
    var isLoadingMoreCalendar = false

    /// Filtered view of the raw sections. Auto-updates whenever the raw list, the filter flag,
    /// or the favourite-teams list changes — no manual refresh required.
    var calendarListSections: [CalendarSection] {
        guard calendarShowFavoritesOnly, !favoriteTeams.isEmpty else { return calendarListRawSections }
        let names = Set(favoriteTeams.map { $0.name.lowercased() })
        return calendarListRawSections.compactMap { section in
            let filtered = section.matches.filter {
                names.contains($0.homeTeam.lowercased()) || names.contains($0.awayTeam.lowercased())
            }
            return filtered.isEmpty ? nil : CalendarSection(date: section.date, matches: filtered)
        }
    }

    static let baseURL = "https://footballia.eu"

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        session = URLSession(configuration: config)
    }

    // MARK: - Dev credentials (loaded from file one level above the repo root)

    static func devCredentials() -> (email: String, password: String)? {
        let url = URL(fileURLWithPath: "/Users/nicholas/Downloads/footballia-credentials.json")
        guard let data = try? Data(contentsOf: url),
              let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let email    = obj["email"],
              let password = obj["password"]
        else { return nil }
        return (email, password)
    }

    // MARK: - Auth

    func login(email: String, password: String) async {
        isLoading  = true
        loginError = nil

        guard let signInURL = URL(string: "\(Self.baseURL)/users/sign_in?locale=en") else {
            loginError = "Invalid URL"; isLoading = false; return
        }

        do {
            var getReq = URLRequest(url: signInURL)
            getReq.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            let (pageData, _) = try await session.data(for: getReq)
            let pageHTML = String(data: pageData, encoding: .utf8) ?? ""
            let csrfToken = extractCSRFToken(from: pageHTML)

            var postReq = URLRequest(url: signInURL)
            postReq.httpMethod = "POST"
            postReq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            postReq.setValue(Self.baseURL, forHTTPHeaderField: "Origin")
            postReq.setValue(signInURL.absoluteString, forHTTPHeaderField: "Referer")
            postReq.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

            var pairs: [(String, String)] = [("utf8", "✓")]
            if let t = csrfToken { pairs.append(("authenticity_token", t)) }
            pairs += [
                ("user[email]",       email),
                ("user[password]",    password),
                ("user[remember_me]", "1"),
                ("commit",            "Sign in"),
            ]
            postReq.httpBody = pairs
                .map { "\($0.0.urlFormEncoded)=\($0.1.urlFormEncoded)" }
                .joined(separator: "&")
                .data(using: .utf8)

            let (_, response) = try await session.data(for: postReq)
            let finalPath = (response as? HTTPURLResponse)?.url?.path ?? "/users/sign_in"
            isLoggedIn = !finalPath.hasPrefix("/users/sign_in")

            if isLoggedIn {
                accountEmail = email
                UserDefaults.standard.set(email, forKey: "footballia.accountEmail")
                async let t: () = loadFavoriteTeams()
                async let m: () = loadMatches()
                async let a: () = refreshMasterAccess()
                _ = await (t, m, a)
            } else {
                loginError = "Invalid email or password. Please try again."
            }
        } catch {
            loginError = "Connection error: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func restoreSession() async {
        isCheckingSession = true
        defer { isCheckingSession = false }

        guard let url = URL(string: "\(Self.baseURL)/?locale=en"),
              let html = try? await fetchHTML(from: url),
              !html.isEmpty else { return }

        // The "Sign in" nav link is only rendered for unauthenticated users
        guard !html.contains("<span>Sign in</span>") else { return }

        isLoggedIn = true
        async let t: () = loadFavoriteTeams()
        async let m: () = loadMatches()
        async let a: () = refreshMasterAccess()
        _ = await (t, m, a)
    }

    func logout() {
        isLoggedIn = false
        matches = []; featuredTeams = []; competitionCategories = []
        searchResults = []; searchSuggestions = []
        calendarCache = [:]; calendarStarted = false
        calendarListRawSections = []; calendarListLoaded = false
        calendarListNextFetchEnd = Date(); calendarShowFavoritesOnly = false
        favoriteTeamSearchResults = []; favoriteTeamSearchError = nil
        isSearchingFavoriteTeams = false; pendingFavoriteSlugs = []
        currentPage = 1; hasNextPage = false; currentFilter = .all; paginationReversed = false
        hasMasterAccess = false; didCheckMasterAccess = false
        accountEmail = nil
        UserDefaults.standard.removeObject(forKey: "footballia.accountEmail")
        UserDefaults.standard.removeObject(forKey: Self.masterAccessKey)
        let s = HTTPCookieStorage.shared
        (s.cookies ?? []).forEach { s.deleteCookie($0) }
    }

    // MARK: - Master access

    /// Loads the calendar page once and infers Master entitlement from whether the
    /// site swapped the calendar out for its "This is a Master feature" upsell notice.
    /// Loads the calendar page once and infers Master entitlement from whether the
    /// site swapped the calendar out for its "This is a Master feature" upsell notice.
    ///
    /// A failed fetch deliberately leaves the cached value alone rather than asserting
    /// "no access": downgrading on a network blip would reorder the tabs and lock the
    /// Calendar for a user who actually is a Master.
    func refreshMasterAccess() async {
        guard let url = URL(string: "\(Self.baseURL)/calendar?locale=en"),
              let html = try? await fetchHTML(from: url), !html.isEmpty else { return }
        hasMasterAccess = !Self.isMasterGated(html)
        didCheckMasterAccess = true
        UserDefaults.standard.set(hasMasterAccess, forKey: Self.masterAccessKey)
    }

    /// Detects the Master paywall notice, e.g.
    /// `<p class="alert alert-success">This is a Master feature. Access this and many more
    ///  features! <a href="/master">Become a Master for as little as €3.99 p/m …</a></p>`
    static func isMasterGated(_ html: String) -> Bool {
        let lower = html.lowercased()
        if lower.contains("this is a master feature") { return true }
        // Fallback in case the copy changes: a success alert that links to the upsell page
        guard let alertRange = lower.range(of: "alert alert-success") else { return false }
        let window = lower[alertRange.lowerBound...].prefix(600)
        return window.contains("become a master")
    }

    // MARK: - Match loading

    func loadMatches(filter: MatchFilter? = nil, page: Int = 1) async {
        let f = filter ?? currentFilter
        if f != currentFilter { paginationReversed = false }
        currentFilter    = f
        currentPage      = page
        isLoadingMatches = true
        defer { isLoadingMatches = false }

        guard let url = URL(string: "\(Self.baseURL)\(f.urlPath)?locale=en&page=\(page)")
        else { return }

        guard let html = try? await fetchHTML(from: url), !html.isEmpty else { return }
        let parsed = parseMatchCards(from: html)
        if !parsed.isEmpty { matches = parsed }
        hasNextPage = html.contains("rel=\"next\"")
    }

    /// Loads a filter's newest matches (the site paginates oldest-first, so that's its last page).
    ///
    /// State is reset synchronously, before the task is spawned, so the drill-down never renders
    /// one frame of the previous screen's matches while the request is in flight.
    func loadMatchesLastPage(filter: MatchFilter) {
        currentFilter      = filter
        paginationReversed = true
        matches            = []
        currentPage        = 1
        hasNextPage        = false
        isLoadingMatches   = true
        Task { await fetchMatchesLastPage(filter: filter) }
    }

    private func fetchMatchesLastPage(filter: MatchFilter) async {
        defer { isLoadingMatches = false }

        guard let page1URL = URL(string: "\(Self.baseURL)\(filter.urlPath)?locale=en&page=1") else { return }
        guard let page1HTML = try? await fetchHTML(from: page1URL), !page1HTML.isEmpty else { return }

        let last = detectLastPage(from: page1HTML)
        currentPage = last

        if last <= 1 {
            let parsed = parseMatchCards(from: page1HTML)
            if !parsed.isEmpty { matches = parsed }
            hasNextPage = false
            return
        }

        guard let lastURL = URL(string: "\(Self.baseURL)\(filter.urlPath)?locale=en&page=\(last)") else { return }
        guard let lastHTML = try? await fetchHTML(from: lastURL), !lastHTML.isEmpty else { return }
        let parsed = parseMatchCards(from: lastHTML)
        if !parsed.isEmpty { matches = parsed }
        hasNextPage = lastHTML.contains("rel=\"next\"")
    }

    private func extractFlagPaths(from html: String) -> (home: String, away: String) {
        var paths: [String] = []
        for part in html.components(separatedBy: "/uploads/team/").dropFirst() {
            let name = String(part.prefix(while: { $0 != "\"" && $0 != "'" && $0 != " " && $0 != "?" }))
            if !name.isEmpty { paths.append("/uploads/team/" + name) }
            if paths.count >= 2 { break }
        }
        return (paths.first ?? "", paths.dropFirst().first ?? "")
    }

    /// Highest page number linked from the pagination strip.
    ///
    /// Scanning is scoped to the `<ul class="pagination">` block because page numbers also appear
    /// in the page's language-switcher links, which always point at page 1. Three separators are
    /// needed: competition pages link `?page=N`, while player/team pages carry an existing query
    /// parameter and link `&amp;page=N` — HTML-escaped, so a bare `&page=` never matches.
    private func detectLastPage(from html: String) -> Int {
        var scope = html
        if let start = html.range(of: "class=\"pagination") {
            let rest = html[start.lowerBound...]
            let end = rest.range(of: "</ul>")?.lowerBound ?? rest.endIndex
            scope = String(rest[..<end])
        }

        var maxPage = 1
        for sep in ["?page=", "&page=", "&amp;page="] {
            for part in scope.components(separatedBy: sep).dropFirst() {
                let numStr = String(part.prefix(while: { $0.isNumber }))
                if let n = Int(numStr) { maxPage = max(maxPage, n) }
            }
        }
        return maxPage
    }

    // MARK: - Featured teams

    /// Loads the favourites list from disk, seeding it on a first run only.
    ///
    /// The list is app-local: footballia.eu has no way to set favourites, so there is nothing to
    /// sync with and the cache is the only source of truth. The homepage's featured-teams strip
    /// seeds it once, after which every change comes from the Profile tab.
    ///
    /// Seeding keys off the *presence of the cache key*, not a non-empty list — otherwise
    /// "Clear All" would be silently undone by the next launch.
    func loadFavoriteTeams() async {
        guard !FavoriteTeamsStore.hasCache else {
            if favoriteTeams.isEmpty { favoriteTeams = FavoriteTeamsStore.load() }
            return
        }
        await loadFeaturedTeams()
        // The user may have edited the list from the Profile tab while the fetch was in flight;
        // that write creates the cache, so the seed must not overwrite it.
        guard !featuredTeams.isEmpty, !FavoriteTeamsStore.hasCache else { return }
        setFavoriteTeams(featuredTeams)
    }

    /// Loads the homepage "top teams" strip — the first-run seed for favourites, and what backs
    /// the Profile tab's "restore defaults" action.
    func loadFeaturedTeams() async {
        guard let url  = URL(string: "\(Self.baseURL)/?locale=en"),
              let html = try? await fetchHTML(from: url) else { return }
        let parsed = parseTeams(from: html)
        if !parsed.isEmpty { featuredTeams = parsed }
    }

    /// Replaces the cached favourites list. The Favorites page renders this same property,
    /// so edits made in the Profile tab show up there immediately and survive relaunches.
    func setFavoriteTeams(_ teams: [Team]) {
        favoriteTeams = teams
        FavoriteTeamsStore.save(teams)
    }

    func isFavorite(slug: String) -> Bool {
        favoriteTeams.contains { $0.slug == slug }
    }

    /// Adds a team picked from search. The suggestion only carries a name and a slug, so the
    /// crest is resolved from the team's own page and cached alongside it — the Favorites page
    /// renders straight from the cache and never re-fetches.
    func addFavoriteTeam(_ suggestion: SearchSuggestion) async {
        let slug = suggestion.slug
        guard !slug.isEmpty, !isFavorite(slug: slug), !pendingFavoriteSlugs.contains(slug) else { return }
        pendingFavoriteSlugs.insert(slug)
        let team = await loadTeamDetails(slug: slug, fallbackName: suggestion.name)
        // A list-wide action taken during the round-trip drops the pending marker: the user's
        // newer intent wins, so this add is abandoned rather than resurrecting the team into a
        // list they just cleared or reset.
        guard pendingFavoriteSlugs.contains(slug) else { return }
        pendingFavoriteSlugs.remove(slug)
        guard !isFavorite(slug: slug) else { return }
        setFavoriteTeams(favoriteTeams + [team])
    }

    func removeFavoriteTeam(_ team: Team) {
        setFavoriteTeams(favoriteTeams.filter { $0.slug != team.slug })
    }

    /// Empties the list. Persisted as an empty list rather than a cleared key so it is not
    /// silently re-seeded from the site on the next launch.
    func clearFavoriteTeams() {
        pendingFavoriteSlugs = []
        setFavoriteTeams([])
    }

    /// Re-seeds the list from the site's featured-teams strip, discarding the user's edits.
    func resetFavoriteTeamsToTopTeams() async {
        if featuredTeams.isEmpty { await loadFeaturedTeams() }
        guard !featuredTeams.isEmpty else { return }
        pendingFavoriteSlugs = []
        setFavoriteTeams(featuredTeams)
    }

    // MARK: - Favourite team search (Profile tab)

    /// Team-name search for the favourites editor, kept out of `searchSuggestions` so the
    /// Search tab's own results are untouched.
    func searchFavoriteTeamCandidates(query: String) async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { clearFavoriteTeamSearch(); return }
        isSearchingFavoriteTeams = true
        favoriteTeamSearchError = nil

        var html: String?
        if let url = URL(string:
            "\(Self.baseURL)\(SearchMode.teams.actionPath)?\(SearchMode.teams.paramName)=\(q.urlFormEncoded)&locale=en") {
            html = try? await fetchHTML(from: url)
        }

        // The caller debounces by cancelling this task on every keystroke, and a cancelled
        // fetch surfaces as a nil result. Bail without touching state so a superseded search
        // can't report a network failure that never happened — or clear the newer one's spinner.
        guard !Task.isCancelled else { return }
        isSearchingFavoriteTeams = false

        guard let html, !html.isEmpty else {
            favoriteTeamSearchResults = []
            favoriteTeamSearchError = "Could not reach the server."
            return
        }

        let suggestions = parseTeamSuggestions(from: html)
        favoriteTeamSearchResults = suggestions
        favoriteTeamSearchError = suggestions.isEmpty ? "No teams found for \"\(q)\"." : nil
    }

    func clearFavoriteTeamSearch() {
        favoriteTeamSearchResults = []
        favoriteTeamSearchError = nil
        isSearchingFavoriteTeams = false
    }

    // MARK: - Team detail

    /// Resolves a team's display name and crest from its own page so a team picked out of
    /// search can be cached as a full favourite.
    ///
    /// Never fails for a missing crest: a favourite with an empty `logoPath` still renders
    /// (cards fall back to initials), so a markup change degrades instead of blocking the add.
    func loadTeamDetails(slug: String, fallbackName: String = "") async -> Team {
        guard let url  = URL(string: "\(Self.baseURL)/teams/\(slug)?locale=en"),
              let html = try? await fetchHTML(from: url)
        else { return parseTeamDetail(from: "", slug: slug, fallbackName: fallbackName) }
        return parseTeamDetail(from: html, slug: slug, fallbackName: fallbackName)
    }

    // MARK: - Competitions

    func loadCompetitions() async {
        guard competitionCategories.isEmpty else { return }
        isLoadingCompetitions = true
        defer { isLoadingCompetitions = false }

        // Try the full competitions listing page first — it has every competition
        if let url = URL(string: "\(Self.baseURL)/competitions?locale=en"),
           let html = try? await fetchHTML(from: url), !html.isEmpty {
            let cats = parseCompetitions(from: html)
            if !cats.isEmpty { competitionCategories = cats; return }
        }

        // Fall back to homepage navigation dropdown
        guard let url  = URL(string: "\(Self.baseURL)/?locale=en"),
              let html = try? await fetchHTML(from: url) else { return }
        let cats = parseCompetitions(from: html)
        if !cats.isEmpty { competitionCategories = cats }
    }

    // MARK: - Search

    /// Fetches player/team suggestions for the given query. Results go into `searchSuggestions`.
    func search(query: String, mode: SearchMode) async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { clearSearch(); return }
        isSearching       = true
        searchError       = nil
        searchSuggestions = []
        defer { isSearching = false }

        let encoded = q.urlFormEncoded
        guard let url = URL(string:
            "\(Self.baseURL)\(mode.actionPath)?\(mode.paramName)=\(encoded)&locale=en")
        else { return }

        guard let html = try? await fetchHTML(from: url), !html.isEmpty else {
            searchError = "Could not reach the server."; return
        }

        let suggestions = mode == .players
            ? parsePlayerSuggestions(from: html)
            : parseTeamSuggestions(from: html)

        if suggestions.isEmpty {
            searchError = "No results found for \"\(q)\"."
        } else {
            searchSuggestions = suggestions
        }
    }

    func clearSearch() {
        searchSuggestions = []; searchResults = []; searchError = nil
        searchCurrentPage = 1; searchHasNextPage = false; searchTotalPages = 1
    }

    /// Loads the most-recent-page matches for a search suggestion into `searchResults`.
    ///
    /// As with `loadMatchesLastPage`, the reset is synchronous so the detail view can't paint a
    /// frame of the previously-viewed player's matches before the request lands.
    func loadMatchesForSuggestion(_ suggestion: SearchSuggestion) {
        searchResults            = []
        searchPaginationReversed = true
        searchCurrentPage        = 1
        searchHasNextPage        = false
        searchTotalPages         = 1
        isLoadingSearchMatches   = true
        Task { await fetchMatchesForSuggestion(suggestion) }
    }

    private func fetchMatchesForSuggestion(_ suggestion: SearchSuggestion) async {
        defer { isLoadingSearchMatches = false }

        guard let page1URL = URL(string: "\(Self.baseURL)\(suggestion.urlPath)?locale=en&page=1") else { return }
        guard let page1HTML = try? await fetchHTML(from: page1URL), !page1HTML.isEmpty else { return }

        let last = detectLastPage(from: page1HTML)
        searchTotalPages = last

        if last <= 1 {
            searchResults = parseMatchCards(from: page1HTML)
            searchCurrentPage = 1
            searchHasNextPage = page1HTML.contains("rel=\"next\"")
            return
        }

        guard let lastURL = URL(string: "\(Self.baseURL)\(suggestion.urlPath)?locale=en&page=\(last)") else { return }
        guard let lastHTML = try? await fetchHTML(from: lastURL), !lastHTML.isEmpty else { return }
        searchResults = parseMatchCards(from: lastHTML)
        searchCurrentPage = last
        searchHasNextPage = lastHTML.contains("rel=\"next\"")
    }

    /// Loads a specific page for a search suggestion (used for pagination).
    func loadSearchPage(_ page: Int, for suggestion: SearchSuggestion) async {
        guard page >= 1 else { return }
        isLoadingSearchMatches = true
        defer { isLoadingSearchMatches = false }

        guard let url = URL(string: "\(Self.baseURL)\(suggestion.urlPath)?locale=en&page=\(page)") else { return }
        guard let html = try? await fetchHTML(from: url), !html.isEmpty else { return }
        let parsed = parseMatchCards(from: html)
        if !parsed.isEmpty { searchResults = parsed }
        searchCurrentPage = page
        searchHasNextPage = html.contains("rel=\"next\"")
    }

    // MARK: - Calendar list loading

    /// First-visit entry point. Loads the most recent 14-day window and is a no-op on revisits.
    func startCalendarList() async {
        guard !calendarListLoaded else { return }
        calendarListLoaded = true
        calendarListNextFetchEnd = Date()
        calendarListRawSections = []
        await loadMoreCalendarList()
    }

    /// Appends the next 14-day window (going further back in time) to the list.
    func loadMoreCalendarList() async {
        guard !isLoadingMoreCalendar else { return }
        isLoadingMoreCalendar = true
        defer { isLoadingMoreCalendar = false }

        let cal = Calendar.current
        let windowEnd = calendarListNextFetchEnd
        guard let windowStart = cal.date(byAdding: .day, value: -14, to: windowEnd) else { return }

        let endYear   = cal.component(.year, from: windowEnd)
        let startYear = cal.component(.year, from: windowStart)
        _ = await fetchCalendarYear(endYear)
        if startYear != endYear { _ = await fetchCalendarYear(startYear) }

        // Iterate from (windowEnd - 1 day) down to windowStart, collecting days that have matches.
        var newSections: [CalendarSection] = []
        guard var current = cal.date(byAdding: .day, value: -1, to: windowEnd) else { return }

        while current >= windowStart {
            let year    = cal.component(.year,  from: current)
            let month   = cal.component(.month, from: current)
            let day     = cal.component(.day,   from: current)
            let dateStr = String(format: "%04d-%02d-%02d", year, month, day)

            if let matches = calendarCache[year]?[dateStr], !matches.isEmpty {
                newSections.append(CalendarSection(date: dateStr, matches: matches))
            }

            guard let prev = cal.date(byAdding: .day, value: -1, to: current) else { break }
            if prev < windowStart { break }
            current = prev
        }

        calendarListRawSections.append(contentsOf: newSections)
        calendarListNextFetchEnd = windowStart
    }

    @discardableResult
    private func fetchCalendarYear(_ year: Int) async -> [String: [Match]] {
        if let cached = calendarCache[year] { return cached }
        guard let url = URL(string: "\(Self.baseURL)/calendar/\(year)?locale=en"),
              let html = try? await fetchHTML(from: url), !html.isEmpty else { return [:] }

        // The calendar is the Master-gated page, so this doubles as the entitlement check.
        if Self.isMasterGated(html) {
            hasMasterAccess = false
            didCheckMasterAccess = true
            UserDefaults.standard.set(false, forKey: Self.masterAccessKey)
            return [:]
        }
        hasMasterAccess = true
        didCheckMasterAccess = true
        UserDefaults.standard.set(true, forKey: Self.masterAccessKey)

        let data = parseCalendarEvents(from: html, year: year)
        // Only a successful fetch is cached, so a network blip retries instead of sticking empty.
        if !data.isEmpty { calendarCache[year] = data }
        return data
    }

    // MARK: - HTML fetch

    func fetchHTML(from url: URL) async throws -> String {
        var req = URLRequest(url: url)
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        if let cookies = HTTPCookieStorage.shared.cookies(for: url) {
            let headers = HTTPCookie.requestHeaderFields(with: cookies)
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        }
        let (data, _) = try await session.data(for: req)
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Match card parser (card layout with thumbnails, e.g. /matches index)

    private func parseMatchCards(from html: String) -> [Match] {
        var results: [Match] = []
        var seen = Set<String>()

        for part in html.components(separatedBy: "href=\"/matches/").dropFirst() {
            let slug = String(part.prefix(while: { $0 != "\"" && $0 != "?" && $0 != "/" }))
            guard !slug.isEmpty, !seen.contains(slug) else { continue }
            seen.insert(slug)

            let window = String(part.prefix(4000))
            guard let hash = extractFirst(
                pattern: #"/cache/matches/([a-f0-9]{32})\.png"#, in: window)
            else { continue }

            let (home, away) = parseTeamNames(from: window, slug: slug)
            let competition  = extractFirst(
                pattern: #"(?:competition|league|cup)[^>]*>\s*([^<]{2,60})"#, in: window) ?? ""
            let date  = extractFirst(pattern: #"\b((?:19|20)\d{2})\b"#, in: window) ?? ""
            let stage = extractFirst(
                pattern: #"(?:stage|round|matchday|phase)[^>]*>\s*([^<]{2,40})"#, in: window) ?? ""
            let flags = extractFlagPaths(from: window)

            results.append(Match(
                id: slug, slug: slug,
                homeTeam: home, awayTeam: away,
                competition: competition.trimmed, stage: stage.trimmed, date: date.trimmed,
                thumbnailHash: hash,
                homeTeamLogoPath: flags.home, awayTeamLogoPath: flags.away
            ))
        }

        // Fall back to table parser for competition/search/player pages that use <tr> layout
        return results.isEmpty ? parseMatchTable(from: html) : results
    }

    // MARK: - Match table parser (table layout used by /competitions/*, /teams/*, search results)
    //
    // Row structure: <tr>
    //   <td>DATE</td>
    //   <td><a href="/matches/SLUG">Home <img alt="Home"> <img alt="Away"> Away</a></td>
    //   <td>COMPETITION</td>  <td>STAGE</td>  <td>YEAR</td>
    // </tr>

    private func parseMatchTable(from html: String) -> [Match] {
        var results: [Match] = []
        var seen = Set<String>()

        for rowChunk in html.components(separatedBy: "<tr").dropFirst() {
            // Skip past the closing > of the <tr ...> tag to get the row body
            guard let gtIdx = rowChunk.firstIndex(of: ">") else { continue }
            let row = String(rowChunk[rowChunk.index(after: gtIdx)...])
            guard row.contains("href=\"/matches/") else { continue }

            // Pull the table cells; handles <td> and <td class="..."> alike
            var tds: [String] = []
            for tdChunk in row.components(separatedBy: "<td").dropFirst() {
                guard let innerGt = tdChunk.firstIndex(of: ">") else { continue }
                let content = String(tdChunk[tdChunk.index(after: innerGt)...])
                guard let endRange = content.range(of: "</td>") else { continue }
                let text = String(content[..<endRange.lowerBound])
                    .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
                    .components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                    .trimmed
                tds.append(text)
            }

            // Extract slug from the match link in this row
            guard let linkRange = row.range(of: "href=\"/matches/") else { continue }
            let afterHref = String(row[linkRange.upperBound...])
            let slug = String(afterHref.prefix(while: { $0 != "\"" && $0 != "?" && $0 != "/" }))
            guard !slug.isEmpty, !seen.contains(slug) else { continue }
            seen.insert(slug)

            // Team names: get flag-image alt values from within the <a> tag
            let linkWindow = String(afterHref.prefix(600))
            var alts: [String] = []
            for altPart in linkWindow.components(separatedBy: "alt=\"").dropFirst() {
                let alt = String(altPart.prefix(while: { $0 != "\"" })).trimmed
                if !alt.isEmpty { alts.append(alt) }
            }
            let home = alts.first ?? (tds.count > 1 ? String(tds[1].prefix(30)) : "")
            let away = alts.dropFirst().first ?? ""

            // tds[0] = date, tds[2] = competition, tds[3] = stage, tds[4] = year
            let date        = tds.count > 0 ? tds[0] : ""
            let competition = tds.count > 2 ? tds[2] : ""
            let stage       = tds.count > 3 ? tds[3] : ""
            let flags = extractFlagPaths(from: linkWindow)

            results.append(Match(
                id: slug, slug: slug,
                homeTeam: home, awayTeam: away,
                competition: competition, stage: stage, date: date,
                thumbnailHash: "",
                homeTeamLogoPath: flags.home, awayTeamLogoPath: flags.away
            ))
        }
        return results.isEmpty ? parseMatchLinks(from: html) : results
    }

    // MARK: - Match link parser (final fallback — player pages and other div+span layouts)
    //
    // Works on any page that has href="/matches/SLUG" links regardless of surrounding structure.

    private func parseMatchLinks(from html: String) -> [Match] {
        var results: [Match] = []
        var seen = Set<String>()

        for part in html.components(separatedBy: "href=\"/matches/").dropFirst() {
            let slug = String(part.prefix(while: { $0 != "\"" && $0 != "?" && $0 != "/" }))
            guard !slug.isEmpty, !seen.contains(slug) else { continue }
            seen.insert(slug)

            let window = String(part.prefix(800))

            // Team names from flag image alt= values inside the link
            var alts: [String] = []
            for altPart in window.components(separatedBy: "alt=\"").dropFirst() {
                let alt = String(altPart.prefix(while: { $0 != "\"" })).trimmed
                if !alt.isEmpty { alts.append(alt) }
            }
            var home = alts.first ?? ""
            var away = alts.dropFirst().first ?? ""

            // Fallback: parse "Home vs. Away" from anchor text
            if home.isEmpty, let endAnchor = window.range(of: "</a>") {
                let inner = String(window[..<endAnchor.lowerBound])
                if let gt = inner.lastIndex(of: ">") {
                    let text = String(inner[inner.index(after: gt)...])
                        .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
                        .components(separatedBy: .whitespacesAndNewlines)
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                        .trimmed
                    for sep in [" vs. ", " vs ", " - ", " – "] {
                        let parts = text.components(separatedBy: sep)
                        if parts.count >= 2 { home = parts[0].trimmed; away = parts[1].trimmed; break }
                    }
                }
            }
            if home.isEmpty { (home, away) = parseTeamNames(from: window, slug: slug) }

            // Metadata from <span> elements following the link
            var spans: [String] = []
            for spanPart in window.components(separatedBy: "<span").dropFirst() {
                if let gt = spanPart.firstIndex(of: ">"),
                   let endSpan = spanPart.range(of: "</span>") {
                    let text = String(spanPart[spanPart.index(after: gt)..<endSpan.lowerBound]).trimmed
                    if !text.isEmpty, !text.contains("<") { spans.append(text) }
                }
            }
            let competition = spans.first ?? ""
            let year        = spans.count > 1 ? spans[1] : ""
            let date        = spans.count > 2 ? spans[2] : year
            let flags = extractFlagPaths(from: window)

            results.append(Match(
                id: slug, slug: slug,
                homeTeam: home, awayTeam: away,
                competition: competition, stage: "", date: date,
                thumbnailHash: "",
                homeTeamLogoPath: flags.home, awayTeamLogoPath: flags.away
            ))
        }
        return results
    }

    // MARK: - Search suggestion parsers

    // Player search: <tr><td><a href="/players/slug">Short</a></td><td>Full Name</td></tr>
    private func parsePlayerSuggestions(from html: String) -> [SearchSuggestion] {
        var results: [SearchSuggestion] = []
        var seen = Set<String>()

        for row in html.components(separatedBy: "<tr>").dropFirst() {
            guard row.contains("href=\"/players/") else { continue }
            guard let linkRange = row.range(of: "href=\"/players/") else { continue }
            let afterHref = String(row[linkRange.upperBound...])
            let slug = String(afterHref.prefix(while: { $0 != "\"" && $0 != "?" && $0 != "/" }))
            guard !slug.isEmpty, !seen.contains(slug) else { continue }
            seen.insert(slug)

            // Full name is in the second <td>
            let tds = row.components(separatedBy: "<td>").dropFirst()
            var fullName = ""
            if tds.count >= 2, let endTd = tds[1].range(of: "</td>") {
                fullName = String(tds[1][..<endTd.lowerBound])
                    .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                    .trimmed
            }
            if fullName.isEmpty {
                fullName = slug.components(separatedBy: "-").map { $0.capitalized }.joined(separator: " ")
            }
            results.append(SearchSuggestion(id: slug, slug: slug, name: fullName, mode: .players))
        }
        return results
    }

    // Team search: links like <a href="/teams/slug">Team Name</a> in the results section
    private func parseTeamSuggestions(from html: String) -> [SearchSuggestion] {
        var results: [SearchSuggestion] = []
        var seen = Set<String>()

        // Narrow to the results section that appears after "found for"
        let area: String
        if let range = html.range(of: "found for ") {
            area = String(html[range.lowerBound...])
        } else {
            area = html
        }

        for part in area.components(separatedBy: "href=\"/teams/").dropFirst() {
            let slug = String(part.prefix(while: { $0 != "\"" && $0 != "?" && $0 != "/" }))
            guard !slug.isEmpty, !seen.contains(slug) else { continue }
            seen.insert(slug)

            let window = String(part.prefix(200))
            var name = ""
            if let gt = window.firstIndex(of: ">"),
               let endAnchor = window.range(of: "</a>") {
                name = String(window[window.index(after: gt)..<endAnchor.lowerBound])
                    .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                    .trimmed
            }
            if name.isEmpty {
                name = slug.components(separatedBy: "-").map { $0.capitalized }.joined(separator: " ")
            }
            results.append(SearchSuggestion(id: slug, slug: slug, name: name, mode: .teams))
            if results.count >= 30 { break }
        }
        return results
    }

    private func parseTeamNames(from html: String, slug: String) -> (String, String) {
        for pattern in [
            #"alt=\"([^\"]+\s[-–]\s[^\"]+)\""#,
            #"alt=\"([^\"]+\svs\.?\s[^\"]+)\""#,
            #"title=\"([^\"]+\s[-–]\s[^\"]+)\""#,
        ] {
            guard let combined = extractFirst(pattern: pattern, in: html) else { continue }
            for sep in [" - ", " – ", " vs ", " VS "] {
                let parts = combined.components(separatedBy: sep)
                if parts.count >= 2 {
                    return (parts[0].trimmed, parts[1...].joined(separator: sep).trimmed)
                }
            }
        }
        let words = slug.components(separatedBy: "-").map { $0.capitalized }
        let mid   = words.count / 2
        return (words[..<mid].joined(separator: " "), words[mid...].joined(separator: " "))
    }

    // MARK: - Team parser

    // The homepage renders its top-teams strip inside a single
    // `<div class="featured_teams …">` containing one `<span class="logo"><a href="/teams/…">`
    // per team. Scope to that container when present so unrelated team links elsewhere on the
    // page can't leak in, falling back to a whole-document scan if the markup changes.
    private func parseTeams(from html: String) -> [Team] {
        let scope: String
        if let start = html.range(of: "featured_teams"),
           let end   = html.range(of: "</div>", range: start.upperBound..<html.endIndex) {
            scope = String(html[start.lowerBound..<end.upperBound])
        } else {
            scope = html
        }

        var results: [Team] = []
        var seen = Set<String>()
        for part in scope.components(separatedBy: "href=\"/teams/").dropFirst() {
            let slug = String(part.prefix(while: { $0 != "\"" && $0 != "?" && $0 != "/" }))
            guard !slug.isEmpty, !seen.contains(slug) else { continue }
            seen.insert(slug)
            let window = String(part.prefix(600))
            let rawName = extractFirst(pattern: #"title=\"([^\"]+)\""#, in: window)
                ?? extractFirst(pattern: #"alt=\"([^\"]+)\""#, in: window)
                ?? Self.name(fromSlug: slug)
            let name = Self.cleanTeamName(rawName)
            let logoPath = extractFirst(pattern: #"src=\"(/uploads/team/[^\"]+)\""#, in: window) ?? ""
            guard !name.isEmpty else { continue }
            results.append(Team(id: slug, slug: slug, name: name, logoPath: logoPath))
        }
        return results
    }

    // A team page exposes its own name and crest through Open Graph tags, e.g.
    //   <meta content="https://footballia.eu/uploads/team/logo/16/medium_….png" property="og:image" />
    //   <meta content="Real Madrid full matches" property="og:title" />
    //
    // Attribute order is matched both ways round because the site emits content-first, but
    // that is a templating detail rather than a guarantee.
    private func parseTeamDetail(from html: String, slug: String, fallbackName: String) -> Team {
        // Scope to <head>, where the og tags live, so a stray content=/property= pair in the
        // body can't win. Falls back to a generous prefix if the closing tag ever goes missing.
        let head: String
        if let end = html.range(of: "</head>", options: .caseInsensitive) {
            head = String(html[html.startIndex..<end.lowerBound])
        } else {
            head = String(html.prefix(60_000))
        }

        let ogImage = extractFirst(pattern: #"property=\"og:image\"[^>]*content=\"([^\"]+)\""#, in: head)
            ?? extractFirst(pattern: #"content=\"([^\"]+)\"[^>]*property=\"og:image\""#, in: head)
        var logoPath = ""
        if var candidate = ogImage {
            if candidate.hasPrefix(Self.baseURL) { candidate.removeFirst(Self.baseURL.count) }
            if candidate.hasPrefix("/uploads/team/") { logoPath = candidate }
        }

        let ogTitle = extractFirst(pattern: #"property=\"og:title\"[^>]*content=\"([^\"]+)\""#, in: head)
            ?? extractFirst(pattern: #"content=\"([^\"]+)\"[^>]*property=\"og:title\""#, in: head)
        let parsedName = ogTitle.map { Self.cleanTeamName($0) } ?? ""
        let name = !parsedName.isEmpty ? parsedName
            : (!fallbackName.trimmed.isEmpty ? fallbackName.trimmed : Self.name(fromSlug: slug))

        return Team(id: slug, slug: slug, name: name, logoPath: logoPath)
    }

    private static func name(fromSlug slug: String) -> String {
        slug.components(separatedBy: "-").map { $0.capitalized }.joined(separator: " ")
    }

    private static func cleanTeamName(_ raw: String) -> String {
        raw.replacingOccurrences(of: " full matches", with: "")
            .replacingOccurrences(of: " matches", with: "")
            .trimmed
    }

    // MARK: - Competition parser

    /// Parses the competitions mega-menu, which nests two levels deep:
    ///
    /// ```
    /// <div class="col-md-3"><h5>Domestic</h5><ul class="links">
    ///   <li>Europe</li>
    ///   <ul class="ul-toggle … sub-menu">
    ///     <li data-keep-open="true"><a title="England"><span class="flag flag-england"></span>England</a>
    ///       <ul class="links" style="display:none;"><li><a href="/competitions/fa-cup" …>FA Cup</a></li>…</ul>
    /// ```
    ///
    /// The Domestic column groups by country (each with a flag sprite class); the national-team
    /// columns group by continent with plain `<li>Europe</li>` headings; "Others" is a flat list
    /// and becomes a single unnamed group.
    ///
    /// Each column is bounded at its closing `</ul></div>` rather than a fixed character budget —
    /// Domestic alone carries ~280 competitions and was previously truncated mid-list.
    private func parseCompetitions(from html: String) -> [CompetitionCategory] {
        var categories: [CompetitionCategory] = []
        var seenSlugs = Set<String>()

        for chunk in html.components(separatedBy: "<div class=\"col-md-3\">").dropFirst() {
            guard chunk.contains("href=\"/competitions/") else { continue }
            let end = chunk.range(of: "</ul></div>")?.lowerBound ?? chunk.endIndex
            let column = String(chunk[..<end])

            let categoryName = (
                extractFirst(pattern: #"<h[4-6][^>]*>\s*([^<]+)\s*</h[4-6]>"#, in: column) ?? "Other"
            ).trimmed

            let groups = parseCompetitionGroups(from: column, category: categoryName, seenSlugs: &seenSlugs)
            if !groups.isEmpty {
                categories.append(CompetitionCategory(id: categoryName, name: categoryName, groups: groups))
            }
        }
        return categories
    }

    /// Splits one catalogue column into its sub-headings.
    ///
    /// Headings are matched in document order so competitions attach to the heading that precedes
    /// them; anything before the first heading becomes an unnamed leading group, which is how a
    /// flat column ("Others") ends up as a single group.
    private func parseCompetitionGroups(from column: String,
                                        category: String,
                                        seenSlugs: inout Set<String>) -> [CompetitionGroup] {
        // A continent heading (`<li>Europe</li>`) or a country row (`<a title="England"><span
        // class="flag flag-england" …>`). Country rows carry the sprite class; continents don't.
        let pattern = #"<li>([^<>]{2,40})</li>|<a title="([^"]+)"><span class="flag flag-([a-z\-]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }

        let ns = column as NSString
        var boundaries: [(offset: Int, name: String, code: String)] = []
        for m in regex.matches(in: column, range: NSRange(location: 0, length: ns.length)) {
            func group(_ i: Int) -> String {
                m.range(at: i).location == NSNotFound ? "" : ns.substring(with: m.range(at: i))
            }
            let name = (group(1).isEmpty ? group(2) : group(1)).trimmed
            guard !name.isEmpty else { continue }
            boundaries.append((m.range.location, name, group(3)))
        }

        var groups: [CompetitionGroup] = []
        let starts = [0] + boundaries.map(\.offset)
        for i in starts.indices {
            let from = starts[i]
            let to = i + 1 < starts.count ? starts[i + 1] : ns.length
            let name = i == 0 ? "" : boundaries[i - 1].name
            let code = i == 0 ? "" : boundaries[i - 1].code
            let section = ns.substring(with: NSRange(location: from, length: to - from))
            let comps = parseCompetitionLinks(from: section, seenSlugs: &seenSlugs)
            guard !comps.isEmpty else { continue }
            groups.append(CompetitionGroup(id: "\(category)/\(name.isEmpty ? "all" : name)",
                                           name: name, countryCode: code, competitions: comps))
        }
        return groups
    }

    private func parseCompetitionLinks(from section: String, seenSlugs: inout Set<String>) -> [Competition] {
        var comps: [Competition] = []
        for part in section.components(separatedBy: "href=\"/competitions/").dropFirst() {
            let slug = String(part.prefix(while: { $0 != "\"" && $0 != "?" && $0 != "/" }))
            guard !slug.isEmpty, !seenSlugs.contains(slug) else { continue }
            seenSlugs.insert(slug)

            let name = (extractFirst(pattern: #"title=\"([^\"]+)\""#, in: String(part.prefix(200)))
                ?? extractFirst(pattern: #">([^<]{2,60})<"#, in: String(part.prefix(100)))
                ?? Self.name(fromSlug: slug)).trimmed

            comps.append(Competition(id: slug, slug: slug, name: Self.decodeEntities(name), logoPath: ""))
        }
        return comps
    }

    /// Minimal entity decoding — competition names carry `&#39;` and `&amp;`
    /// (e.g. "Full Members&#39; Cup").
    static func decodeEntities(_ text: String) -> String {
        text.replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    // MARK: - Calendar helpers

    /// Turns the FullCalendar `events: [...]` payload into matches keyed by ISO `yyyy-MM-dd`.
    ///
    /// There is no per-day endpoint — `/matches?date=` and `/calendar?date=` are both ignored by
    /// the server — so `/calendar/<year>` embedding the whole year is the only source for both
    /// the highlighted days and each day's match list.
    private func parseCalendarEvents(from html: String, year: Int) -> [String: [Match]] {
        guard let json = extractEventsArray(from: html),
              let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [:] }

        var byDate: [String: [Match]] = [:]
        var seenPerDate: [String: Set<String>] = [:]

        for event in array {
            let date = event["start"] as? String ?? ""
            // The feed occasionally carries neighbouring years' fixtures; keep the page's own.
            guard date.count == 10, Int(date.prefix(4)) == year else { continue }

            let url = event["url"] as? String ?? ""
            guard let hrefRange = url.range(of: "/matches/") else { continue }
            let slug = String(url[hrefRange.upperBound...].prefix(while: { $0 != "?" && $0 != "/" }))
            guard !slug.isEmpty, seenPerDate[date, default: []].insert(slug).inserted else { continue }

            let (homeName, homeLogo) = parseCalendarTeam(event["home_team"] as? String ?? "")
            let (awayName, awayLogo) = parseCalendarTeam(event["away_team"] as? String ?? "")

            byDate[date, default: []].append(Match(
                id: slug, slug: slug,
                homeTeam: homeName, awayTeam: awayName,
                competition: (event["competition"] as? String ?? "").trimmed,
                stage: "",
                date: Self.formatCalendarDate(date),
                thumbnailHash: "",
                homeTeamLogoPath: homeLogo, awayTeamLogoPath: awayLogo
            ))
        }
        return byDate
    }

    /// Extracts the balanced `[...]` literal following `events:` in the page's setup script.
    ///
    /// Candidates are filtered twice because third-party scripts on the page declare similar
    /// keys: an identifier that merely *ends* in "events" (New Relic's `generic_events:`) is
    /// skipped, as is any `events:` not followed by an array literal.
    ///
    /// Scanning is done over UTF-8 bytes rather than `Character`s: the page is ~2 MB, and only
    /// ASCII delimiters matter here — a multi-byte sequence can never contain an ASCII byte, so
    /// team names in any script survive untouched while the scan stays linear and cheap.
    private func extractEventsArray(from html: String) -> String? {
        let bytes = Array(html.utf8)
        let needle = Array("events:".utf8)
        guard bytes.count > needle.count else { return nil }

        func isIdentifierByte(_ b: UInt8) -> Bool {
            (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) ||
            (b >= 0x61 && b <= 0x7A) || b == UInt8(ascii: "_") || b == UInt8(ascii: ".")
        }

        for i in 0...(bytes.count - needle.count) {
            guard bytes[i] == needle[0], Array(bytes[i..<(i + needle.count)]) == needle else { continue }
            if i > 0, isIdentifierByte(bytes[i - 1]) { continue }

            var start = i + needle.count
            while start < bytes.count, bytes[start] == 0x20 || bytes[start] == 0x09
                    || bytes[start] == 0x0A || bytes[start] == 0x0D { start += 1 }
            guard start < bytes.count, bytes[start] == UInt8(ascii: "[") else { continue }
            if let array = Self.balancedArray(bytes, from: start) { return array }
        }
        return nil
    }

    private static func balancedArray(_ bytes: [UInt8], from start: Int) -> String? {
        var depth = 0
        var inString = false
        var escaped = false
        for i in start..<bytes.count {
            let b = bytes[i]
            if inString {
                if escaped { escaped = false }
                else if b == UInt8(ascii: "\\") { escaped = true }
                else if b == UInt8(ascii: "\"") { inString = false }
                continue
            }
            switch b {
            case UInt8(ascii: "\""): inString = true
            case UInt8(ascii: "["):  depth += 1
            case UInt8(ascii: "]"):
                depth -= 1
                if depth == 0 { return String(decoding: bytes[start...i], as: UTF8.self) }
            default: break
            }
        }
        return nil
    }

    /// Splits a calendar `home_team`/`away_team` HTML fragment into (display name, crest path).
    private func parseCalendarTeam(_ fragment: String) -> (String, String) {
        guard !fragment.isEmpty else { return ("", "") }
        let logo = extractFirst(pattern: #"src=\"(/uploads/team/[^\"]+)\""#, in: fragment) ?? ""
        var name = fragment
        if let last = fragment.range(of: "</span>", options: .backwards) {
            name = String(fragment[last.upperBound...])
        }
        name = name.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression).trimmed
        if name.isEmpty { name = extractFirst(pattern: #"alt=\"([^\"]+)\""#, in: fragment) ?? "" }
        return (Self.decodeEntities(name), logo)
    }

    /// `2026-01-03` → `January 3, 2026`, matching the date style used by the table layouts.
    private static func formatCalendarDate(_ iso: String) -> String {
        let parts = iso.components(separatedBy: "-")
        guard parts.count == 3,
              let month = Int(parts[1]), (1...12).contains(month),
              let day = Int(parts[2]) else { return iso }
        let names = ["January","February","March","April","May","June",
                     "July","August","September","October","November","December"]
        return "\(names[month - 1]) \(day), \(parts[0])"
    }

    // MARK: - Auth helpers

    private func extractCSRFToken(from html: String) -> String? {
        extractFirst(pattern: #"name="authenticity_token"[^>]*value="([^"]+)""#, in: html)
            ?? extractFirst(pattern: #"value="([^"]+)"[^>]*name="authenticity_token""#, in: html)
            ?? extractFirst(pattern: #"<meta name="csrf-token" content="([^"]+)""#, in: html)
    }

    private func extractFirst(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    var urlFormEncoded: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
