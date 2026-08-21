import SwiftUI

struct MainView: View {
    @Environment(FootballiaService.self) private var service
    @State private var selectedSection: SidebarSection = .favorites
    @State private var selectedMatch: Match? = nil

    private let sections = SidebarSection.ordered

    var body: some View {
        ZStack {
            #if os(tvOS)
            tvShell
                .allowsHitTesting(selectedMatch == nil)
            #elseif os(iOS)
            mobileShell
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
    #elseif os(iOS)
    // On mobile the navigation lives in a top bar instead of a left sidebar. The app logo is
    // shown only in landscape (portrait is too narrow to spare the width); in either orientation
    // the menu itself sits along the top.
    private var mobileShell: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            VStack(spacing: 0) {
                TopMenuBar(sections: sections, selected: $selectedSection, showLogo: isLandscape)
                    .background(Color(red: 0.06, green: 0.06, blue: 0.08))

                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)

                content(for: selectedSection)
                    .background(Color(red: 0.08, green: 0.08, blue: 0.10))
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
        #if os(iOS)
        case .favorites:    FavoritesView(mode: .teams)
        case .recents:      FavoritesView(mode: .recents)
        #else
        case .favorites:    FavoritesView(mode: .combined)
        case .recents:      FavoritesView(mode: .combined)
        #endif
        case .competitions: CompetitionsView()
        case .search:       SearchView()
        case .calendar:     CalendarView()
        case .profile:      ProfileView()
        }
    }
}
