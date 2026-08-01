import Foundation

/// Disk-backed cache for the user's favourite teams.
///
/// The list is seeded once, from the site's homepage "top teams" strip, the first time the app
/// successfully loads it. From then on it is owned by the user: the Profile tab's Favorite Teams
/// editor adds/removes/clears entries and the Favorites page renders whatever is cached, so the
/// list stays stable even as the site rotates its own strip.
///
/// Note `hasCache` — not emptiness — is what marks the list as seeded. Clearing the list from the
/// editor saves an empty array so it is not silently repopulated on the next launch; `clear()`
/// wipes the key entirely and hands ownership back to the seeding path.
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
