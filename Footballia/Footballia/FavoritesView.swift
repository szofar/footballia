import SwiftUI

/// The Favorites page: a grid of cards for the cached top-teams list.
/// Selecting a team drills into that team's matches, most recent first.
struct FavoritesView: View {
    @Environment(FootballiaService.self) private var service
    @State private var selectedTeam: Team? = nil
    @State private var selectedMatch: Match? = nil

    var body: some View {
        ZStack {
            if let team = selectedTeam {
                VStack(spacing: 0) {
                    backBar(title: team.name)
                    VideoGridView(
                        title: team.name,
                        matches: service.matches,
                        isLoading: service.isLoadingMatches,
                        currentPage: service.currentPage,
                        hasNextPage: service.hasNextPage,
                        isReversed: service.paginationReversed,
                        onSelect: { match in
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                selectedMatch = match
                            }
                        },
                        onNextPage: {
                            Task { await service.loadMatches(
                                filter: .team(team.slug),
                                page: service.currentPage + 1
                            )}
                        },
                        onPreviousPage: {
                            Task { await service.loadMatches(
                                filter: .team(team.slug),
                                page: service.currentPage - 1
                            )}
                        }
                    )
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .allowsHitTesting(selectedMatch == nil)
            } else {
                teamGrid
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .allowsHitTesting(selectedMatch == nil)
            }

            if let match = selectedMatch {
                VideoPlayerOverlay(match: match) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        selectedMatch = nil
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .center)))
                .zIndex(10)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: selectedTeam != nil)
        .task {
            // Seeds the cache on first ever launch. An empty list with a cache present means the
            // user cleared it on purpose, so it is left alone rather than silently repopulated.
            await service.loadFavoriteTeams()
        }
    }

    // MARK: - Team grid

    private var teamGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Favorites")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                    Text(service.favoriteTeams.isEmpty
                         ? "Your teams will appear here"
                         : "\(service.favoriteTeams.count) teams")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.35))
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 30)

                if service.favoriteTeams.isEmpty {
                    VStack(spacing: 10) {
                        if FavoriteTeamsStore.hasCache {
                            Text("No favorite teams")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                            Text("Add teams from Profile › Favorite Teams.")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.3))
                        } else {
                            ProgressView().tint(.green)
                            Text("Loading teams…")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.3))
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 16)]
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(service.favoriteTeams) { team in
                            TeamCardView(team: team) {
                                selectedTeam = team
                                service.loadMatchesLastPage(filter: .team(team.slug))
                            }
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                }
            }
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
    }

    private var horizontalPadding: CGFloat {
        #if os(tvOS)
        return 100
        #else
        return 28
        #endif
    }

    // MARK: - Back bar

    private func backBar(title: String) -> some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    selectedTeam = nil
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Favorites")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.55))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)

            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(Color(red: 0.07, green: 0.07, blue: 0.09))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
    }
}

// MARK: - Team card

struct TeamCardView: View {
    let team: Team
    let onTap: () -> Void
    #if os(tvOS)
    @Environment(\.isFocused) private var isFocused
    private var isHighlighted: Bool { isFocused }
    #else
    @State private var isHovered = false
    private var isHighlighted: Bool { isHovered }
    #endif

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                // A nil URL (no crest resolved) never reaches AsyncImage's .failure phase, so
                // the placeholder has to be chosen up front rather than in the phase switch.
                Group {
                    if let logoURL = team.logoURL {
                        AsyncImage(url: logoURL) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fit)
                            case .failure:
                                logoPlaceholder
                            case .empty:
                                Color.clear
                            @unknown default:
                                logoPlaceholder
                            }
                        }
                    } else {
                        logoPlaceholder
                    }
                }
                .frame(width: 64, height: 64)

                Text(team.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .background(Color(red: 0.12, green: 0.12, blue: 0.14))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(isHighlighted ? 0.16 : 0.05), lineWidth: 1)
            )
            .scaleEffect(isHighlighted ? 1.03 : 1.0)
            .shadow(color: .black.opacity(isHighlighted ? 0.45 : 0.18),
                    radius: isHighlighted ? 16 : 7,
                    y: isHighlighted ? 9 : 4)
        }
        .buttonStyle(.plain)
        #if os(tvOS)
        .focusEffectDisabled()
        #else
        .onHover { isHovered = $0 }
        #endif
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isHighlighted)
    }

    private var logoPlaceholder: some View {
        Circle()
            .fill(Color.white.opacity(0.08))
            .overlay(
                Text(String(team.name.prefix(2)).uppercased())
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
            )
    }
}
