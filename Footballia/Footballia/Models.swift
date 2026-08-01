import Foundation

// MARK: - Sidebar navigation

enum SidebarSection: String, CaseIterable, Identifiable {
    case favorites    = "Favorites"
    case competitions = "Competitions"
    case search       = "Search"
    case calendar     = "Calendar"
    case profile      = "Profile"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .favorites:    return "star.fill"
        case .competitions: return "trophy.fill"
        case .search:       return "magnifyingglass"
        case .calendar:     return "calendar"
        case .profile:      return "person.fill"
        }
    }

    /// Tab order depends on Master entitlement: Master users land on the Calendar,
    /// everyone else lands on Favorites with the (gated) Calendar demoted.
    static func ordered(hasMasterAccess: Bool) -> [SidebarSection] {
        hasMasterAccess
            ? [.calendar, .favorites, .competitions, .search, .profile]
            : [.favorites, .competitions, .calendar, .search, .profile]
    }
}

// MARK: - Match filter

enum MatchFilter: Equatable {
    case all
    case team(String)
    case player(String)
    case competition(String)
    case date(String)   // "YYYY-MM-DD"

    var urlPath: String {
        switch self {
        case .all:                return "/matches"
        case .team(let s):        return "/teams/\(s)"
        case .player(let s):      return "/players/\(s)"
        case .competition(let s): return "/competitions/\(s)"
        case .date:               return "/matches"
        }
    }

    var extraQuery: String {
        if case .date(let d) = self { return "&date=\(d)" }
        return ""
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

struct CompetitionCategory: Identifiable {
    let id: String      // category heading text
    let name: String
    let competitions: [Competition]
}

// MARK: - Team

struct Team: Identifiable, Hashable, Codable {
    let id: String
    let slug: String
    let name: String
    let logoPath: String

    var logoURL: URL? {
        URL(string: "\(FootballiaService.baseURL)\(logoPath)")
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
