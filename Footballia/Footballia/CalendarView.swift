import SwiftUI

struct CalendarView: View {
    @Environment(FootballiaService.self) private var service
    @State private var selectedMatch: Match? = nil
    @FocusState private var loadMoreFocused: Bool

    var body: some View {
        ZStack {
            if service.didCheckMasterAccess && !service.hasMasterAccess {
                masterUpsell
            } else {
                calendarBody
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
        .task { await service.startCalendarList() }
    }

    // MARK: - Master gate

    private var masterUpsell: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.15))
            Text("Calendar")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white.opacity(0.7))
            Text("This is a Master feature.")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
            Text("Sign up for Master access on footballia.eu to browse matches by date — along with many more features.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.35))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 28)
    }

    // MARK: - Calendar body

    private var calendarBody: some View {
        VStack(spacing: 0) {
            calendarHeader
            calendarContent
        }
    }

    private var calendarHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Calendar")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                Text("Browse matches by date")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.35))
            }
            Spacer()
            if service.isLoadingMoreCalendar {
                ProgressView().tint(.green).controlSize(.small)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .background(Color(red: 0.07, green: 0.07, blue: 0.09))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
    }

    @ViewBuilder
    private var calendarContent: some View {
        let sections = service.calendarListSections
        if sections.isEmpty && !service.isLoadingMoreCalendar {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sections) { section in
                        dateSectionRow(section: section,
                                       isLast: section.id == sections.last?.id)
                    }

                    #if !os(tvOS)
                    loadMoreButton
                        .padding(.horizontal, 28)
                        .padding(.top, 24)
                    #endif

                    favoritesToggle
                        .padding(.horizontal, 28)
                        .padding(.top, 20)
                        .padding(.bottom, 28)
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ProgressView().tint(.green)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Date section row

    private func dateSectionRow(section: CalendarSection, isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(formatDate(section.date))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 28)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 16) {
                    ForEach(section.matches) { match in
                        matchCardButton(for: match)
                    }

                    #if os(tvOS)
                    if isLast {
                        loadMoreCard
                    }
                    #endif
                }
                .padding(.horizontal, 28)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    // MARK: - Match card

    @ViewBuilder
    private func matchCardButton(for match: Match) -> some View {
        #if os(tvOS)
        Button { selectedMatch = match } label: {
            VideoCardView(match: match)
                .frame(width: 300)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        #else
        VideoCardView(match: match)
            .frame(width: 260)
            .onTapGesture { selectedMatch = match }
        #endif
    }

    // MARK: - Load more (tvOS card, appended to last section's horizontal row)

    private var loadMoreCard: some View {
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

    // MARK: - Load more (macOS button below sections)

    private var loadMoreButton: some View {
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

    // MARK: - Favorites toggle

    private var favoritesToggle: some View {
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

    private func formatDate(_ iso: String) -> String {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: iso) else { return iso }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: date)
    }
}
