import SwiftUI

/// Minimal account tab: who's signed in, Master entitlement, and sign out.
struct ProfileView: View {
    @Environment(FootballiaService.self) private var service
    @State private var confirmingLogout = false
    @State private var teamQuery = ""
    @State private var confirmingClear = false
    @FocusState private var teamFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Profile")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                    Text("Account and access")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.35))
                }
                .padding(.top, 30)

                accountCard
                masterCard
                favoriteTeamsCard
                signOutButton

                Spacer(minLength: 20)
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        // Live team search for the favourites editor: cancelled and restarted on every keystroke.
        .task(id: teamQuery) {
            let q = teamQuery.trimmingCharacters(in: .whitespaces)
            guard !q.isEmpty else { service.clearFavoriteTeamSearch(); return }
            try? await Task.sleep(for: .seconds(0.3))
            guard !Task.isCancelled else { return }
            await service.searchFavoriteTeamCandidates(query: q)
        }
    }

    private var horizontalPadding: CGFloat {
        #if os(tvOS)
        return 100
        #else
        return 28
        #endif
    }

    // MARK: - Account

    private var accountCard: some View {
        card {
            HStack(spacing: 14) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 38))
                    .foregroundColor(.green.opacity(0.8))

                VStack(alignment: .leading, spacing: 3) {
                    Text(service.accountEmail ?? "Signed in")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text("footballia.eu")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.35))
                }

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Master status

    private var masterCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: service.hasMasterAccess ? "crown.fill" : "lock.fill")
                        .font(.system(size: 16))
                        .foregroundColor(service.hasMasterAccess ? .green : .white.opacity(0.3))

                    Text(service.hasMasterAccess ? "Master access" : "No Master access")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)

                    Spacer(minLength: 0)

                    if !service.didCheckMasterAccess {
                        ProgressView().tint(.green).controlSize(.small)
                    }
                }

                Text(service.hasMasterAccess
                     ? "Master features such as the Calendar are unlocked on this account."
                     : "The Calendar is a Master feature. Visit footballia.eu/master in a browser to subscribe, then reopen the app.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Favourite teams

    /// Editor for the favourites list rendered by the Favorites page. Both read the same
    /// `service.favoriteTeams`, so add/remove/clear shows up there immediately and is persisted.
    private var favoriteTeamsCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.green)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Favorite Teams")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                        Text(service.favoriteTeams.isEmpty
                             ? "No teams — search below to add some"
                             : "\(service.favoriteTeams.count) teams shown on the Favorites page")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.4))
                    }

                    Spacer(minLength: 0)
                }

                teamSearchField

                if !teamQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                    teamSearchResults
                }

                if !service.favoriteTeams.isEmpty {
                    Text("YOUR LIST")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.3))

                    VStack(spacing: 2) {
                        ForEach(service.favoriteTeams) { team in
                            favoriteRow(team)
                        }
                    }
                }

                HStack(spacing: 10) {
                    smallButton(
                        title: confirmingClear ? "Click again to confirm" : "Clear All",
                        systemImage: "xmark.circle",
                        destructive: true,
                        highlighted: confirmingClear,
                        enabled: !service.favoriteTeams.isEmpty
                    ) {
                        if confirmingClear {
                            service.clearFavoriteTeams()
                            confirmingClear = false
                        } else {
                            withAnimation(.easeInOut(duration: 0.15)) { confirmingClear = true }
                        }
                    }

                    smallButton(
                        title: "Restore Defaults",
                        systemImage: "arrow.clockwise",
                        destructive: false,
                        highlighted: false,
                        enabled: true
                    ) {
                        confirmingClear = false
                        Task { await service.resetFavoriteTeamsToTopTeams() }
                    }
                }
            }
        }
    }

    private var teamSearchField: some View {
        HStack(spacing: 8) {
            if service.isSearchingFavoriteTeams {
                ProgressView().tint(.green).controlSize(.small)
            } else {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.white.opacity(teamFieldFocused ? 0.7 : 0.3))
                    .font(.system(size: 13))
            }

            TextField("Search teams to add…", text: $teamQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .focused($teamFieldFocused)

            if !teamQuery.isEmpty {
                Button {
                    teamQuery = ""
                    service.clearFavoriteTeamSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.3))
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(teamFieldFocused ? 0.2 : 0.0), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.15), value: teamFieldFocused)
    }

    @ViewBuilder
    private var teamSearchResults: some View {
        if let error = service.favoriteTeamSearchError {
            Text(error)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.35))
        } else if service.favoriteTeamSearchResults.isEmpty && service.isSearchingFavoriteTeams {
            Text("Searching…")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.35))
        } else {
            VStack(spacing: 2) {
                ForEach(service.favoriteTeamSearchResults) { suggestion in
                    suggestionRow(suggestion)
                }
            }
        }
    }

    private func suggestionRow(_ suggestion: SearchSuggestion) -> some View {
        let isFavorite = service.isFavorite(slug: suggestion.slug)
        let isPending  = service.pendingFavoriteSlugs.contains(suggestion.slug)

        return Button {
            guard !isPending else { return }
            if isFavorite {
                if let team = service.favoriteTeams.first(where: { $0.slug == suggestion.slug }) {
                    service.removeFavoriteTeam(team)
                }
            } else {
                Task { await service.addFavoriteTeam(suggestion) }
            }
        } label: {
            HStack(spacing: 10) {
                Text(suggestion.name)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isPending {
                    ProgressView().tint(.green).controlSize(.small)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: isFavorite ? "checkmark" : "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text(isFavorite ? "Added" : "Add")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(isFavorite ? .green : .white.opacity(0.55))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func favoriteRow(_ team: Team) -> some View {
        HStack(spacing: 10) {
            // A nil URL (no crest resolved) never reaches AsyncImage's .failure phase, so the
            // initials placeholder has to be chosen up front rather than in the phase switch.
            Group {
                if let logoURL = team.logoURL {
                    AsyncImage(url: logoURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fit)
                        case .empty:
                            Color.clear
                        default:
                            teamInitials(team)
                        }
                    }
                } else {
                    teamInitials(team)
                }
            }
            .frame(width: 24, height: 24)

            Text(team.name)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .lineLimit(1)

            Spacer(minLength: 0)

            Button {
                service.removeFavoriteTeam(team)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(team.name)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func teamInitials(_ team: Team) -> some View {
        Text(String(team.name.prefix(2)).uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white.opacity(0.4))
    }

    private func smallButton(
        title: String,
        systemImage: String,
        destructive: Bool,
        highlighted: Bool,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(
                !enabled ? .white.opacity(0.25)
                : highlighted ? .white
                : (destructive ? .red.opacity(0.85) : .white.opacity(0.7))
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(highlighted ? Color.red.opacity(0.75) : Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Sign out

    private var signOutButton: some View {
        Button {
            if confirmingLogout {
                service.logout()
            } else {
                withAnimation(.easeInOut(duration: 0.15)) { confirmingLogout = true }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                Text(confirmingLogout ? "Tap again to confirm" : "Sign Out")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(confirmingLogout ? .white : .red.opacity(0.85))
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(confirmingLogout ? Color.red.opacity(0.75) : Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.red.opacity(confirmingLogout ? 0 : 0.28), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Card chrome

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.12, green: 0.12, blue: 0.14))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
            )
    }
}
