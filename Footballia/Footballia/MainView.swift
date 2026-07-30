import SwiftUI

struct MainView: View {
    @Environment(FootballiaService.self) private var service
    @State private var selectedSection: SidebarSection = .home
    @State private var selectedMatch: Match? = nil

    var body: some View {
        ZStack {
            appShell
                .allowsHitTesting(selectedMatch == nil)

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
        .frame(minWidth: 1000, idealWidth: 1280, minHeight: 660, idealHeight: 800)
    }

    private var appShell: some View {
        HStack(spacing: 0) {
            SidebarView(selected: $selectedSection, onLogout: service.logout)
                .frame(width: 72)
                .background(Color(red: 0.06, green: 0.06, blue: 0.08))

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 1)

            sectionContent
                .background(Color(red: 0.08, green: 0.08, blue: 0.10))
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .home:          homeContent
        case .competitions:  CompetitionsView()
        case .search:        SearchView()
        case .calendar:      CalendarView()
        case .profile:       profilePlaceholder
        }
    }

    // MARK: - Home

    private var homeContent: some View {
        VStack(spacing: 0) {
            if !service.featuredTeams.isEmpty {
                TeamSelectorView(
                    teams: service.featuredTeams,
                    selectedSlug: teamSlugFromFilter
                ) { slug in
                    if let slug {
                        Task { await service.loadMatchesLastPage(filter: .team(slug)) }
                    } else {
                        Task { await service.loadMatches(filter: .all) }
                    }
                }
            }

            VideoGridView(
                title: homeSectionTitle,
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
                    Task { await service.loadMatches(page: service.currentPage + 1) }
                },
                onPreviousPage: {
                    Task { await service.loadMatches(page: service.currentPage - 1) }
                }
            )
        }
    }

    private var homeSectionTitle: String {
        if case .team(let slug) = service.currentFilter {
            return service.featuredTeams.first(where: { $0.slug == slug })?.name ?? "Matches"
        }
        return "Latest Matches"
    }

    private var teamSlugFromFilter: String? {
        if case .team(let slug) = service.currentFilter { return slug }
        return nil
    }

    // MARK: - Profile placeholder

    private var profilePlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.circle")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.12))
            Text("Profile")
                .font(.title2.weight(.semibold))
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
