import Foundation

// MARK: - Sidebar navigation

enum SidebarSection: String, CaseIterable, Identifiable {
    case favorites    = "Favorites"
    case recents      = "Recents"
    case competitions = "Competitions"
    case search       = "Search"
    case calendar     = "Calendar"
    case profile      = "Profile"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .favorites:    return "star.fill"
        case .recents:      return "clock.fill"
        case .competitions: return "trophy.fill"
        case .search:       return "magnifyingglass"
        case .calendar:     return "calendar"
        case .profile:      return "person.fill"
        }
    }

    /// Fixed navigation order. Calendar is Master-gated, but the order deliberately does not
    /// depend on entitlement: reordering once the check came back made the tabs jump under the
    /// user's cursor a moment after launch.
    ///
    /// On mobile the Favorites page's team grid and recent-matches feed are split into two
    /// separate root tabs (`.favorites` / `.recents`); on tvOS/macOS both live on the one
    /// Favorites page, so `.recents` is omitted there.
    static let ordered: [SidebarSection] = {
        #if os(iOS)
        return [.favorites, .recents, .competitions, .calendar, .search, .profile]
        #else
        return [.favorites, .competitions, .calendar, .search, .profile]
        #endif
    }()
}

// MARK: - Match filter

/// Note there is deliberately no "by date" case: `/matches?date=…` is silently ignored by the
/// site and returns the unfiltered index. Calendar days are served from the year's event feed
/// instead — see `FootballiaService.startCalendar`.
enum MatchFilter: Equatable {
    case all
    case team(String)
    case player(String)
    case competition(String)

    var urlPath: String {
        switch self {
        case .all:                return "/matches"
        case .team(let s):        return "/teams/\(s)"
        case .player(let s):      return "/players/\(s)"
        case .competition(let s): return "/competitions/\(s)"
        }
    }
}

// MARK: - Search

enum SearchMode: String, CaseIterable, Identifiable {
    case players = "Players"
    case teams   = "Teams"
    var id: String { rawValue }

    var actionPath: String {
        switch self {
        case .players: return "/search_by_player"
        case .teams:   return "/search_by_team"
        }
    }

    var paramName: String {
        switch self {
        case .players: return "player_name"
        case .teams:   return "team_name"
        }
    }

    var placeholder: String {
        switch self {
        case .players: return "Type player name or nickname"
        case .teams:   return "Type team name"
        }
    }
}

// MARK: - Search suggestion

struct SearchSuggestion: Identifiable, Hashable {
    let id: String      // slug
    let slug: String
    let name: String
    let mode: SearchMode

    var urlPath: String {
        switch mode {
        case .players: return "/players/\(slug)"
        case .teams:   return "/teams/\(slug)"
        }
    }
}

// MARK: - Competition catalogue

struct Competition: Identifiable, Hashable {
    let id: String
    let slug: String
    let name: String
    let logoPath: String

    var logoURL: URL? {
        logoPath.isEmpty ? nil : URL(string: "\(FootballiaService.baseURL)\(logoPath)")
    }
}

/// A run of competitions under one sub-heading of a catalogue category.
///
/// The site's mega-menu nests two levels deep: a category (`<h5>Domestic</h5>`) holds either a
/// flat list of competitions or sub-headings — continents for the national-team columns, and
/// countries for Domestic, where each country also carries a CSS sprite class (`flag flag-es`)
/// that `countryCode` preserves. A category with no sub-headings is modelled as a single group
/// with an empty `name`.
struct CompetitionGroup: Identifiable {
    let id: String
    let name: String
    let countryCode: String
    let competitions: [Competition]

    var flagEmoji: String? { Self.flagEmoji(for: countryCode) }

    /// Flag codes the site uses that aren't ISO 3166-1 alpha-2, mapped to their closest emoji.
    private static let nonISOFlags: [String: String] = [
        "england":  "\u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}",
        "scotland": "\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}",
        "wales":    "\u{1F3F4}\u{E0067}\u{E0062}\u{E0077}\u{E006C}\u{E0073}\u{E007F}",
        // No dedicated emoji exists for either; fall back to the sovereign state's flag.
        "northern-ireland": "\u{1F1EC}\u{1F1E7}",
        "kosovo":           "\u{1F1FD}\u{1F1F0}"
    ]

    /// Renders a footballia flag class suffix (`flag-es` → `es`) as a Unicode flag.
    ///
    /// The site only ships flags as a CSS sprite sheet, so there is no image URL to load; an ISO
    /// alpha-2 code maps directly onto the two regional-indicator scalars instead. Returns nil
    /// for anything unrecognised so callers can omit the icon rather than draw a tofu box.
    static func flagEmoji(for code: String) -> String? {
        let c = code.trimmingCharacters(in: .whitespaces).lowercased()
        guard !c.isEmpty else { return nil }
        if let mapped = nonISOFlags[c] { return mapped }
        guard c.count == 2, c.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        var flag = ""
        for ch in c.unicodeScalars {
            guard let scalar = UnicodeScalar(0x1F1E6 + ch.value - 0x61) else { return nil }
            flag.unicodeScalars.append(scalar)
        }
        return flag
    }
}

struct CompetitionCategory: Identifiable {
    let id: String      // category heading text
    let name: String
    let groups: [CompetitionGroup]

    var competitions: [Competition] { groups.flatMap(\.competitions) }
}

// MARK: - Team

struct Team: Identifiable, Hashable, Codable {
    let id: String
    let slug: String
    let name: String
    let logoPath: String

    var logoURL: URL? {
        logoPath.isEmpty ? nil : URL(string: "\(FootballiaService.baseURL)\(logoPath)")
    }
}

// MARK: - Match

struct Match: Identifiable, Hashable {
    let id: String
    let slug: String
    let homeTeam: String
    let awayTeam: String
    let competition: String
    let stage: String
    let date: String
    let thumbnailHash: String
    let homeTeamLogoPath: String
    let awayTeamLogoPath: String

    var thumbnailURL: URL? {
        thumbnailHash.isEmpty ? nil :
            URL(string: "\(FootballiaService.baseURL)/cache/matches/\(thumbnailHash).png")
    }

    var homeTeamLogoURL: URL? {
        homeTeamLogoPath.isEmpty ? nil :
            URL(string: "\(FootballiaService.baseURL)\(homeTeamLogoPath)")
    }

    var awayTeamLogoURL: URL? {
        awayTeamLogoPath.isEmpty ? nil :
            URL(string: "\(FootballiaService.baseURL)\(awayTeamLogoPath)")
    }

    var matchPageURL: URL? {
        URL(string: "\(FootballiaService.baseURL)/matches/\(slug)?locale=en")
    }

    var title: String { "\(homeTeam) vs \(awayTeam)" }
}
