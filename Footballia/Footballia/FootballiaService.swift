import Foundation
import Observation
import WebKit

@MainActor
@Observable
final class FootballiaService {

    // MARK: - Auth state
    var isLoggedIn  = false
    var isLoading   = false
    var loginError: String?

    // MARK: - Match browsing state
    var matches: [Match] = []
    var isLoadingMatches = false
    var currentPage  = 1
    var hasNextPage  = false
    var currentFilter: MatchFilter = .all
    var paginationReversed = false

    // MARK: - Featured teams (home page strip)
    var featuredTeams: [Team] = []

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

    // MARK: - Calendar
    var calendarMatchDays: Set<Int> = []
    var calendarYear  = Calendar.current.component(.year,  from: Date())
    var calendarMonth = Calendar.current.component(.month, from: Date())
    var isLoadingCalendar = false

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
                async let t: () = loadFeaturedTeams()
                async let m: () = loadMatches()
                _ = await (t, m)
            } else {
                loginError = "Invalid email or password. Please try again."
            }
        } catch {
            loginError = "Connection error: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func logout() {
        isLoggedIn = false
        matches = []; featuredTeams = []; competitionCategories = []
        searchResults = []; searchSuggestions = []; calendarMatchDays = []
        currentPage = 1; hasNextPage = false; currentFilter = .all; paginationReversed = false
        let s = HTTPCookieStorage.shared
        (s.cookies ?? []).forEach { s.deleteCookie($0) }
    }

    // MARK: - Match loading

    func loadMatches(filter: MatchFilter? = nil, page: Int = 1) async {
        let f = filter ?? currentFilter
        if f != currentFilter { paginationReversed = false }
        currentFilter    = f
        currentPage      = page
        isLoadingMatches = true
        defer { isLoadingMatches = false }

        guard let url = URL(string:
            "\(Self.baseURL)\(f.urlPath)?locale=en&page=\(page)\(f.extraQuery)")
        else { return }

        guard let html = try? await fetchHTML(from: url), !html.isEmpty else { return }
        let parsed = parseMatchCards(from: html)
        if !parsed.isEmpty { matches = parsed }
        hasNextPage = html.contains("rel=\"next\"")
    }

    /// Fetches page 1 to discover the last page number, then loads that page.
    /// Used for competitions so the most-recent matches show first.
    func loadMatchesLastPage(filter: MatchFilter) async {
        currentFilter    = filter
        paginationReversed = true
        isLoadingMatches = true
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

    private func detectLastPage(from html: String) -> Int {
        // Scan every ?page=N in pagination links and take the maximum
        var maxPage = 1
        for part in html.components(separatedBy: "?page=").dropFirst() {
            let numStr = String(part.prefix(while: { $0.isNumber }))
            if let n = Int(numStr) { maxPage = max(maxPage, n) }
        }
        return maxPage
    }

    // MARK: - Featured teams

    func loadFeaturedTeams() async {
        guard let url  = URL(string: "\(Self.baseURL)/?locale=en"),
              let html = try? await fetchHTML(from: url) else { return }
        let parsed = parseTeams(from: html)
        if !parsed.isEmpty { featuredTeams = parsed }
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
    func loadMatchesForSuggestion(_ suggestion: SearchSuggestion) async {
        isLoadingSearchMatches = true
        searchResults = []
        searchPaginationReversed = true
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

    // MARK: - Calendar

    func loadCalendar(year: Int? = nil, month: Int? = nil) async {
        let y = year  ?? calendarYear
        let m = month ?? calendarMonth
        calendarYear  = y
        calendarMonth = m
        isLoadingCalendar = true
        defer { isLoadingCalendar = false }

        let dateStr = String(format: "%04d-%02d-01", y, m)
        guard let url = URL(string: "\(Self.baseURL)/calendar?date=\(dateStr)&locale=en"),
              let html = try? await fetchHTML(from: url) else { return }

        var days = parseCalendarDays(from: html, year: y, month: m)

        // Fallback: bare /calendar returns most-recent month; use it to seed year/month
        if days.isEmpty {
            guard let fallback = URL(string: "\(Self.baseURL)/calendar?locale=en"),
                  let fbHTML = try? await fetchHTML(from: fallback) else { return }
            if let (fy, fm) = extractCalendarYearMonth(from: fbHTML) {
                calendarYear = fy; calendarMonth = fm
                days = parseCalendarDays(from: fbHTML, year: fy, month: fm)
            }
        }
        calendarMatchDays = days
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

    private func parseTeams(from html: String) -> [Team] {
        var results: [Team] = []
        var seen = Set<String>()
        for part in html.components(separatedBy: "href=\"/teams/").dropFirst() {
            let slug = String(part.prefix(while: { $0 != "\"" && $0 != "?" && $0 != "/" }))
            guard !slug.isEmpty, !seen.contains(slug) else { continue }
            seen.insert(slug)
            let window = String(part.prefix(600))
            let rawName = extractFirst(pattern: #"title=\"([^\"]+)\""#, in: window)
                ?? extractFirst(pattern: #"alt=\"([^\"]+)\""#, in: window)
                ?? slug.components(separatedBy: "-").map { $0.capitalized }.joined(separator: " ")
            let name = rawName
                .replacingOccurrences(of: " full matches", with: "")
                .replacingOccurrences(of: " matches", with: "")
                .trimmed
            let logoPath = extractFirst(pattern: #"src=\"(/uploads/team/[^\"]+)\""#, in: window) ?? ""
            guard !name.isEmpty else { continue }
            results.append(Team(id: slug, slug: slug, name: name, logoPath: logoPath))
        }
        return results
    }

    // MARK: - Competition parser

    // The competitions menu/page uses col-md-3 column divs, each with an h4/h5/h6 category
    // header and competition anchor tags — e.g.:
    //   <div class="col-md-3"><h5>England</h5>
    //     <ul><li><a href="/competitions/premier-league" title="Premier League">…</a></li> …
    //
    // Splits on "col-md-3" (not exact-quoted) so it handles additional CSS classes
    // such as class="col-md-3 dropdown-col". Window is 16 000 chars to fit large country sections.
    private func parseCompetitions(from html: String) -> [CompetitionCategory] {
        var categories: [CompetitionCategory] = []
        var seenSlugs = Set<String>()

        for chunk in html.components(separatedBy: "col-md-3").dropFirst() {
            guard chunk.contains("href=\"/competitions/") else { continue }

            let window = String(chunk.prefix(16000))

            let categoryName = (
                extractFirst(pattern: #"<h[4-6][^>]*>\s*([^<]+)\s*</h[4-6]>"#, in: window) ?? "Other"
            ).trimmed

            var comps: [Competition] = []
            for part in window.components(separatedBy: "href=\"/competitions/").dropFirst() {
                let slug = String(part.prefix(while: { $0 != "\"" && $0 != "?" && $0 != "/" }))
                guard !slug.isEmpty, !seenSlugs.contains(slug) else { continue }
                seenSlugs.insert(slug)

                let name = extractFirst(pattern: #"title=\"([^\"]+)\""#, in: String(part.prefix(200)))
                    ?? extractFirst(pattern: #">([^<]{2,60})<"#, in: String(part.prefix(100)))
                    ?? slug.components(separatedBy: "-").map { $0.capitalized }.joined(separator: " ")

                comps.append(Competition(id: slug, slug: slug, name: name.trimmed, logoPath: ""))
            }

            if !comps.isEmpty {
                categories.append(CompetitionCategory(id: categoryName, name: categoryName,
                                                      competitions: comps))
            }
        }
        return categories
    }

    // MARK: - Calendar helpers

    private func parseCalendarDays(from html: String, year: Int, month: Int) -> Set<Int> {
        var days = Set<Int>()
        let prefix = String(format: "%04d-%02d-", year, month)
        for part in html.components(separatedBy: "?date=").dropFirst() {
            let d = String(part.prefix(10))
            guard d.hasPrefix(prefix), d.count == 10, let day = Int(d.suffix(2)) else { continue }
            days.insert(day)
        }
        return days
    }

    private func extractCalendarYearMonth(from html: String) -> (Int, Int)? {
        let months = ["January","February","March","April","May","June",
                      "July","August","September","October","November","December"]
        for (i, name) in months.enumerated() {
            if let yearStr = extractFirst(pattern: "\(name)\\s+(\\d{4})", in: html),
               let year = Int(yearStr) {
                return (year, i + 1)
            }
        }
        return nil
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
