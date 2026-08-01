import Foundation

/// Disk-backed cache for the user's favourite teams.
///
/// The list is seeded once, from the site's homepage "top teams" strip, the first time the app
/// successfully loads it. From then on it is read from `UserDefaults` so it stays stable even as
/// the site rotates its own strip — and so an editing UI can own it later.
enum FavoriteTeamsStore {
    private static let key = "footballia.favoriteTeams.v1"

    static var hasCache: Bool {
        UserDefaults.standard.data(forKey: key) != nil
    }

    static func load() -> [Team] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let teams = try? JSONDecoder().decode([Team].self, from: data)
        else { return [] }
        return teams
    }

    static func save(_ teams: [Team]) {
        guard let data = try? JSONEncoder().encode(teams) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
