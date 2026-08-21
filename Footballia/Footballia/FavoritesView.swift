import SwiftUI

/// Which sections the Favorites page shows. On tvOS/macOS both live on one page
/// (`.combined`); on mobile they're promoted to separate root tabs (`.teams` / `.recents`).
enum FavoritesMode {
    case combined
    case teams
    case recents
}

/// The Favorites page: a grid of cards for the cached top-teams list, followed by a
/// rolling two-week match feed from the calendar. Selecting a team drills into that
/// team's matches, most recent first.
struct FavoritesView: View {
    var mode: FavoritesMode = .combined
    @Environment(FootballiaService.self) private var service
    @State private var selectedTeam: Team? = nil
    @State private var selectedMatch: Match? = nil
    @FocusState private var loadMoreFocused: Bool

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
            let stale = service.isStale("favorites")
            async let fav: () = service.loadFavoriteTeams()
            async let cal: () = service.startCalendarList(force: stale)
            _ = await (fav, cal)
            service.markLoaded("favorites")
        }
    }

    // MARK: - Team grid + calendar feed

    private var teamGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 5) {
                    Text(mode == .recents ? "Recents" : "Favorites")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                    Text(headerSubtitle)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.35))
                }
                .padding(.horizontal, hPad)
                .padding(.top, 30)
                .padding(.bottom, 24)

                if mode != .recents {
                    teamCardsSection
                }

                if mode != .teams {
                    let sections = service.calendarListSections
                    if !sections.isEmpty || service.isLoadingMoreCalendar {
                        calendarFeed(sections: sections)
                    }
                }
            }
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
    }

    private var headerSubtitle: String {
        switch mode {
        case .recents:
            return "Recent matches from your calendar"
        case .teams, .combined:
            return service.favoriteTeams.isEmpty
                ? "Your teams will appear here"
                : "\(service.favoriteTeams.count) teams"
        }
    }

    @ViewBuilder
    private var teamCardsSection: some View {
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
            .frame(maxWidth: .infinity, minHeight: 160)
        } else {
            #if os(tvOS)
            let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 16)]
            #elseif os(iOS)
            let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
            #else
            let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
            #endif
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(service.favoriteTeams) { team in
                    TeamCardView(team: team) {
                        selectedTeam = team
                        service.loadMatchesLastPage(filter: .team(team.slug))
                    }
                }
            }
            .padding(.horizontal, hPad)
        }
    }

    // MARK: - Calendar feed

    private func calendarFeed(sections: [CalendarSection]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Divider + section header
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
                .padding(.horizontal, hPad)
                .padding(.top, 32)

            if service.isLoadingMoreCalendar {
                HStack {
                    Spacer()
                    ProgressView().tint(.green).controlSize(.small)
                }
                .padding(.horizontal, hPad)
                .padding(.top, 20)
                .padding(.bottom, 16)
            }

            // Date section rows
            ForEach(sections) { section in
                calendarSectionRow(section: section,
                                   isLast: section.id == sections.last?.id)
            }

            #if !os(tvOS)
            // macOS: load-more button sits below the sections
            calendarLoadMoreButton
                .padding(.horizontal, hPad)
                .padding(.top, 20)
            #endif

            // Favorites-only toggle
            calendarFavoritesToggle
                .padding(.horizontal, hPad)
                .padding(.top, 16)
        }
    }

    private func calendarSectionRow(section: CalendarSection, isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(formatCalendarDate(section.date))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.55))
                .padding(.horizontal, hPad)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 16) {
                    ForEach(section.matches) { match in
                        calendarMatchCard(for: match)
                    }

                    #if os(tvOS)
                    if isLast { calendarLoadMoreCard }
                    #endif
                }
                .padding(.horizontal, hPad)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func calendarMatchCard(for match: Match) -> some View {
        #if os(tvOS)
        Button { selectedMatch = match } label: {
            VideoCardView(match: match).frame(width: 300)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        #else
        VideoCardView(match: match)
            .frame(width: 260)
            .onTapGesture { selectedMatch = match }
        #endif
    }

    // tvOS: "More weeks" card appended to the right of the last date row
    private var calendarLoadMoreCard: some View {
        Button {
            Task { await service.loadMoreCalendarList() }
        } label: {
            VStack(spacing: 10) {
                if service.isLoadingMoreCalendar {
                    ProgressView().tint(.green).scaleEffect(0.85)
                } else {
                    Image(systemName: "chevron.right.2")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.green)
                    Text("More\nweeks")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.45))
                        .multilineTextAlignment(.center)
                }
            }
            .frame(width: 100, height: 168)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .focused($loadMoreFocused)
        .onChange(of: loadMoreFocused) { _, focused in
            if focused && !service.isLoadingMoreCalendar {
                Task { await service.loadMoreCalendarList() }
            }
        }
    }

    // macOS: text button below the date rows
    private var calendarLoadMoreButton: some View {
        Button {
            Task { await service.loadMoreCalendarList() }
        } label: {
            HStack(spacing: 8) {
                if service.isLoadingMoreCalendar {
                    ProgressView().tint(.green).controlSize(.small)
                    Text("Loading…")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.4))
                } else {
                    Text("Load previous weeks")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.green)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.green.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.green.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(service.isLoadingMoreCalendar)
    }

    private var calendarFavoritesToggle: some View {
        HStack {
            Text("Show only favorite teams")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
            Spacer()
            Toggle("", isOn: Binding(
                get: { service.calendarShowFavoritesOnly },
                set: { service.calendarShowFavoritesOnly = $0 }
            ))
            .tint(.green)
            .labelsHidden()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private var hPad: CGFloat {
        #if os(tvOS)
        return 100
        #else
        return 28
        #endif
    }

    private func formatCalendarDate(_ iso: String) -> String {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: iso) else { return iso }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: date)
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
                Group {
                    if let logoURL = team.logoURL {
                        CachedAsyncImage(url: logoURL) { phase in
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
