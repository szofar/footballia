import SwiftUI

struct MainView: View {
    @Environment(FootballiaService.self) private var service
    @State private var selectedSection: SidebarSection = .favorites
    @State private var selectedMatch: Match? = nil
    @State private var didApplyInitialSection = false

    private var sections: [SidebarSection] {
        SidebarSection.ordered(hasMasterAccess: service.hasMasterAccess)
    }

    var body: some View {
        ZStack {
            #if os(tvOS)
            tvShell
                .allowsHitTesting(selectedMatch == nil)
            #else
            appShell
                .allowsHitTesting(selectedMatch == nil)
            #endif

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
        #if os(macOS)
        .frame(minWidth: 1000, idealWidth: 1280, minHeight: 660, idealHeight: 800)
        #endif
        // Land on the first tab for this entitlement, but only once, so the user is
        // never yanked off a tab they navigated to themselves.
        .onChange(of: service.didCheckMasterAccess, initial: true) { _, checked in
            guard checked, !didApplyInitialSection else { return }
            didApplyInitialSection = true
            selectedSection = sections.first ?? .favorites
        }
    }

    #if os(tvOS)
    private var tvShell: some View {
        TabView(selection: $selectedSection) {
            ForEach(sections) { section in
                content(for: section)
                    .tabItem { Label(section.rawValue, systemImage: section.systemImage) }
                    .tag(section)
            }
        }
    }
    #else
    private var appShell: some View {
        HStack(spacing: 0) {
            SidebarView(sections: sections, selected: $selectedSection)
                .frame(width: 72)
                .background(Color(red: 0.06, green: 0.06, blue: 0.08))

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 1)

            content(for: selectedSection)
                .background(Color(red: 0.08, green: 0.08, blue: 0.10))
        }
    }
    #endif

    @ViewBuilder
    private func content(for section: SidebarSection) -> some View {
        switch section {
        case .favorites:    FavoritesView()
        case .competitions: CompetitionsView()
        case .search:       SearchView()
        case .calendar:     CalendarView()
        case .profile:      ProfileView()
        }
    }
}
